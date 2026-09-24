import SwiftUI
import SwiftData

struct VideoItem: Identifiable {
    let id: String
    let asset: AssetSummary
    var compressionState: CompressionState = .waiting
    var selectedPreset: CompressionPreset = CompressionPreset.presets[0]
}

@Observable
@MainActor
final class VideoCompressionViewModel {
    var videos: [VideoItem] = []
    var isLoading = true
    private(set) var hasLoadedVideos = false
    var selectedIds: Set<String> = []
    var isCompressing = false
    var errorMessage: String?
    /// Per-batch outcome counts, set once the loop finishes so the view can
    /// show a single summary / success haptic (COMP-09, COMP-11).
    var batchSummary: CompressionBatchSummary?
    private(set) var isCancelled = false
    /// Which step of the replace batch is running, for the bottom bar.
    private(set) var phase: ReplacePhase = .idle
    /// Saved copies whose originals are still in the library (the user tapped
    /// "Don't Allow"). The view offers Try Again / Remove Copies.
    var keptOriginals: [PendingOriginal] = []
    /// False once the screen is gone. A decline then has no alert to show,
    /// so the kept copies are settled as "both kept" instead of staying
    /// pending (which made a later reconcile ask to delete them, unexplained).
    var isOnScreen = true

    private func storeKept(_ kept: [PendingOriginal]) {
        if isOnScreen {
            keptOriginals = kept
        } else {
            for item in kept { item.swap.finalizeKeptBoth() }
        }
    }
    /// The batch mutation loop, owned by the VM so leaving the screen can
    /// cancel it instead of orphaning the mutation loop (COMP-08).
    private var batchTask: Task<Void, Never>?

    var defaultPresetId: String {
        get { AppPreferences.defaultCompressionPresetID() }
        set { AppPreferences.saveDefaultCompressionPresetID(newValue) }
    }

    private let photoService = PhotoLibraryService.shared
    private let compressionService: VideoCompressionService

    init() {
        compressionService = VideoCompressionService(photoService: photoService)
    }

    var defaultPreset: CompressionPreset {
        CompressionPreset.presets.first { $0.id == defaultPresetId } ?? CompressionPreset.presets[0]
    }

    /// Cached sort ORDER (ids only, C13 parity): sort keys are immutable
    /// (`fileSize`), so the order is recomputed only when the id set changes
    /// and survives progress-tick mutations. Items are always mapped from the
    /// current `videos`, so preset/state edits never render stale copies.
    private var cachedSortedVideoOrder: [String] = []
    private var cachedSortedVideoIdSet: Set<String> = []

    var sortedVideos: [VideoItem] {
        let ids = Set(videos.map(\.id))
        if ids != cachedSortedVideoIdSet {
            cachedSortedVideoOrder = videos.sorted { $0.asset.fileSize > $1.asset.fileSize }.map(\.id)
            cachedSortedVideoIdSet = ids
        }
        let byId = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        return cachedSortedVideoOrder.compactMap { byId[$0] }
    }

    var selectedSize: Int64 {
        videos.totalFileSize(selectedIds: selectedIds, idOf: \.id, sizeOf: { $0.asset.fileSize })
    }

    func loadIfNeeded() async {
        guard !hasLoadedVideos else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let videoAssets = await photoService.fetchAssetsByMediaType(.video)
        videos = videoAssets.map { VideoItem(id: $0.id, asset: $0, selectedPreset: defaultPreset) }
        hasLoadedVideos = true
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh spinner.
    func refresh() async {
        // Don't replace `videos` out from under an in-flight compression loop —
        // its per-id index lookups would miss and savings/records would be lost.
        guard !isCompressing else { return }
        errorMessage = nil
        let videoAssets = await photoService.fetchAssetsByMediaType(.video)
        // Per-row quality picks survive a refresh.
        let presets = Dictionary(videos.map { ($0.id, $0.selectedPreset) }, uniquingKeysWith: { first, _ in first })
        videos = videoAssets.map { VideoItem(id: $0.id, asset: $0, selectedPreset: presets[$0.id] ?? defaultPreset) }
        hasLoadedVideos = true
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    var allSelected: Bool {
        !videos.isEmpty && selectedIds.count == videos.count
    }

    func selectAll() {
        selectedIds = Set(videos.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    /// The bottom-bar quality picker: one choice for every selected video.
    func setPresetForSelected(_ preset: CompressionPreset) {
        for index in videos.indices where selectedIds.contains(videos[index].id) {
            videos[index].selectedPreset = preset
        }
    }

    /// The shared preset of the selection, or nil when it is mixed.
    var selectedPreset: CompressionPreset? {
        let ids = Set(videos.filter { selectedIds.contains($0.id) }.map(\.selectedPreset.id))
        guard ids.count == 1, let id = ids.first else { return nil }
        return CompressionPreset.presets.first { $0.id == id }
    }

    func setPreset(_ preset: CompressionPreset, for videoId: String) {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            videos[index].selectedPreset = preset
        }
    }

    func estimateSize(for video: VideoItem) -> Int64 {
        // Synchronous estimation based on bitrate * duration (D8: keyed off
        // the EFFECTIVE preset — a 720p source with the default 1080p preset
        // selected exports at 720p, so estimating at 1080p's bitrate showed
        // ~2× the real result).
        let effective = VideoCompressionService.effectivePreset(for: video.asset, selected: video.selectedPreset)
        let bitrate: Int64
        switch effective.id {
        case "1080p": bitrate = 8_000_000
        case "720p": bitrate = 4_000_000
        case "480p": bitrate = 2_000_000
        default: bitrate = 6_000_000
        }
        return (bitrate / 8) * Int64(max(video.asset.duration, 1))
    }

    var insufficientDiskSpace = false
    var isDeleting = false

    /// Deletes a single video (used by the per-row trash button and the
    /// in-preview Delete action).
    func deleteVideo(id: String) async -> Bool {
        guard !isDeleting, !isCompressing else { return !videos.contains(where: { $0.id == id }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: [id])
            videos.removeAll { $0.id == id }
            selectedIds.remove(id)
        } catch {
            errorMessage = error.localizedDescription
        }
        return !videos.contains(where: { $0.id == id })
    }

    /// Starts the batch on a VM-owned task so the screen can cancel it on
    /// disappear (COMP-08). Idempotent while a batch is running. Blocked while
    /// a single-item delete is in flight: `deleteVideo` mutates `videos` after
    /// its await, which would shift rows under the batch's fixed `indexById`.
    func startBatchCompression(modelContext: ModelContext) {
        guard batchTask == nil, !isDeleting else { return }
        batchTask = Task { [weak self] in
            await self?.compressSelected(modelContext: modelContext)
            self?.batchTask = nil
        }
    }

    /// Requests cancellation of the running batch: sets the flag the loop
    /// checks and cancels the VM-owned task (which also stops any in-flight
    /// save in the services). Copies already saved still go to the one
    /// delete-originals commit.
    func cancelCompression() {
        isCancelled = true
        batchTask?.cancel()
    }

    /// "Try Again" on the Originals Kept alert: one more delete commit.
    /// Clears `keptOriginals` synchronously so the alert does not re-present.
    func retryRemovingOriginals() {
        let items = keptOriginals
        keptOriginals = []
        guard !items.isEmpty else { return }
        isCompressing = true
        Task {
            phase = .removingOriginals(count: items.count)
            let outcome = await OriginalsCommit.commit(items)
            phase = .idle
            let done = Set(outcome.committed.map(\.assetId))
            videos.removeAll { done.contains($0.id) }
            selectedIds.subtract(done)
            isCompressing = false
            storeKept(outcome.kept)
        }
    }

    /// "Remove Copies" on the Originals Kept alert: the originals stay, the
    /// new copies go.
    func removeCopies() {
        let items = keptOriginals
        keptOriginals = []
        guard !items.isEmpty else { return }
        isCompressing = true
        Task {
            // A decline leaves both versions: say so instead of going quiet.
            if await !OriginalsCommit.removeCopies(items) {
                errorMessage = "Copies kept. Both versions are in your library; delete either one in Photos."
            }
            let ids = Set(items.map(\.assetId))
            // Declined rows stay non-eligible: their copies are still in the
            // library (journaled as kept), so offering Compress again would
            // strand another duplicate. `replacementId` is nilled when the
            // copy is removed, so rows whose copies are gone go back to waiting.
            let keptIds = Set(items.filter { $0.swap.replacementId != nil }.map(\.assetId))
            for index in videos.indices where ids.contains(videos[index].id) {
                if keptIds.contains(videos[index].id) {
                    videos[index].compressionState = .keptOriginal(reason: "Original kept — both versions in your library")
                } else {
                    videos[index].compressionState = .waiting
                }
            }
            isCompressing = false
        }
    }

    func compressSelected(modelContext: ModelContext) async {
        // `!isDeleting`: a single-item delete may be past its guard and about
        // to mutate `videos` — starting the batch now would hand it an
        // `indexById` its own trailing `removeAll` (plus the delete's) invalidates.
        guard !selectedIds.isEmpty, !isCompressing, !isDeleting else { return }
        errorMessage = nil
        batchSummary = nil

        // Check available disk space before starting
        insufficientDiskSpace = false
        let totalSelectedSize = selectedSize
        if let freeSpace = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           freeSpace < Int64(Double(totalSelectedSize) * 2.0) {
            insufficientDiskSpace = true
            return
        }

        isCompressing = true
        isCancelled = false

        // COMP-16: skip assets that already have a usable copy — completed
        // swaps, no-savings skips, and kept-both declines — so they are never
        // re-encoded (quality degradation, duplicate copies). Only rows that
        // still name a copy count: failed rows and skips whose copies were
        // removed (Remove Copies accepted) stay eligible for another try.
        let previouslyCompletedIds: Set<String> = ((try? modelContext.fetch(
            FetchDescriptor<CompressionRecord>(predicate: #Predicate { $0.outcome != "pending" && $0.outcome != "failed" })
        )) ?? []).reduce(into: Set<String>()) {
            if $1.replacementAssetLocalIdentifier != nil { $0.insert($1.assetLocalIdentifier) }
        }

        // D1: resolve leftovers from any interrupted swap BEFORE the batch —
        // otherwise a stranded duplicate could be re-compressed or double-counted.
        await CompressionJournal.reconcile(modelContext: modelContext)

        // COMP-12: deterministic batch order (descending file size, id tiebreak)
        // matching the on-screen list instead of nondeterministic Set iteration.
        // Owned by CompressionBatchRunner.run; the VM only builds the inputs.
        // Idempotent overwrite: PhotoKit identifiers are unique, so a
        // repeated id (shouldn't happen) just re-records the same size
        // instead of trapping the scan.
        let fileSizes = videos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }

        // O(1) row lookup for the batch: `refresh()` and per-item delete are
        // both no-ops while `isCompressing`, so no structural mutation can
        // reorder rows mid-batch and these indices stay valid until the
        // terminal removeAll below.
        let indexById = Dictionary(uniqueKeysWithValues: videos.enumerated().map { ($1.id, $0) })

        let handlers = CompressionBatchRunner.Handlers(
            setExporting: { [weak self] index, progress in
                guard let self else { return }
                self.videos[index].compressionState = .exporting(progress)
            },
            setKeptOriginal: { [weak self] index, reason in
                guard let self else { return }
                self.videos[index].compressionState = .keptOriginal(reason: reason)
            },
            setCompleted: { [weak self] index, saved in
                guard let self else { return }
                self.videos[index].compressionState = .completed(savedBytes: saved)
            },
            setFailed: { [weak self] index, message in
                guard let self else { return }
                self.videos[index].compressionState = .failed(message)
            },
            setWaiting: { [weak self] index in
                guard let self else { return }
                self.videos[index].compressionState = .waiting
            },
            setCopySaved: { [weak self] index in
                guard let self else { return }
                self.videos[index].compressionState = .copySaved
            },
            setPhase: { [weak self] phase in
                self?.phase = phase
            }
        )

        let isSizeUnknown: @MainActor @Sendable (Error) -> Bool = { error in
            guard let compressionError = error as? CompressionError else { return false }
            if case .sizeUnknown = compressionError { return true }
            return false
        }

        let result = await CompressionBatchRunner.run(
            selected: selectedIds,
            fileSizes: fileSizes,
            indexById: indexById,
            alreadyCompletedIds: previouslyCompletedIds,
            isCancelled: { [weak self] in self?.isCancelled ?? true },
            isSizeUnknown: isSizeUnknown,
            modelContext: modelContext,
            handlers: handlers,
            execute: { [weak self] id, index, report in
                guard let self else { throw CancellationError() }
                // Captured before the await so the failure audit trail below stays
                // accurate even if the row vanishes from `videos` mid-export.
                let originalSize = self.videos[index].asset.fileSize
                // COMP-10: never export with a preset larger than the source.
                let preset = VideoCompressionService.effectivePreset(
                    for: self.videos[index].asset,
                    selected: self.videos[index].selectedPreset
                )
                // D1: journal the swap BEFORE it starts, so a crash mid-swap is
                // recoverable on next load instead of leaving a permanent duplicate.
                // Throws when the pending row is not durable — that aborts this
                // item before any library write (no journal, no swap).
                let swap = try CompressionSwap(
                    mediaType: .video,
                    assetId: id,
                    originalSize: originalSize,
                    // D15: history rows show the clean preset id ("1080p"),
                    // matching the photo stack and the tests, instead of the raw
                    // AVFoundation constant.
                    exportPreset: preset.id,
                    modelContext: modelContext
                )
                do {
                    let compressResult = try await self.compressionService.compressVideo(
                        assetId: id,
                        preset: preset,
                        // D1: the library write is about to start — from here a crash
                        // could strand a copy whose id the journal never learned.
                        onSaveWillCommit: {
                            swap.markSaveAttempted()
                        },
                        // D1: the replacement id lands in the journal the moment the
                        // save commits — the earliest crash point that can strand a copy.
                        onReplacementSaved: { replacementId, compressedSize in
                            swap.recordReplacement(id: replacementId, size: compressedSize)
                        },
                        onProgress: { progress in
                            report(progress)
                        }
                    )

                    if compressResult.skipped {
                        // COMP-04: no-savings items stay in the list with an
                        // explanation instead of silently vanishing.
                        swap.finalizeSkipped()
                        self.videos[index].compressionState = .keptOriginal(reason: "No savings — kept original")
                        return .skipped
                    }

                    // Step 1 done. The original stays until the runner's single
                    // delete commit, which finalizes this journal row.
                    return .saved(PendingOriginal(
                        assetId: id,
                        originalSize: compressResult.originalSize,
                        compressedSize: compressResult.compressedSize,
                        swap: swap
                    ))
                } catch {
                    if self.isCancelled || error is CancellationError {
                        // User cancelled mid-item: reset the row and stop the loop. A
                        // cancel is not a failure — History must not render a red
                        // badge for something the summary reports as cancelled.
                        await swap.markSkipped(assetId: id)
                        throw error
                    }
                    if let compressionError = error as? CompressionError,
                       case .sizeUnknown = compressionError {
                        // COMP-07: iCloud-only / unknown size — leave the original
                        // alone. An intentional skip, not a failure.
                        await swap.markSkipped(assetId: id)
                        throw error
                    }
                    await swap.markFailed(assetId: id)
                    throw error
                }
            }
        )
        let successfulIds = result.successfulIds
        let completedCount = result.summary.completed
        let failedCount = result.summary.failed
        let skippedCount = result.summary.skipped

        // COMP-04: remove only successfully compressed (and deleted) items;
        // skipped ones stay so the user can see why they were left alone.
        videos.removeAll { successfulIds.contains($0.id) }
        selectedIds.subtract(successfulIds)
        storeKept(result.kept)
        isCompressing = false
        batchSummary = CompressionBatchSummary(
            completed: completedCount,
            failed: failedCount,
            skipped: skippedCount,
            cancelled: isCancelled
        )

        // COMP-11: one aggregated summary after the batch instead of an alert
        // popping per item mid-loop.
        if failedCount > 0 {
            let attempted = completedCount + failedCount
            errorMessage = "Compressed \(completedCount) of \(attempted). \(failedCount) failed."
        }
    }
}
