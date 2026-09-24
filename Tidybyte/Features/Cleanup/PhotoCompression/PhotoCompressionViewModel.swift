import SwiftUI
import SwiftData

struct PhotoItem: Identifiable {
    let id: String
    let asset: AssetSummary
    var compressionState: CompressionState = .waiting
    var selectedPreset: PhotoCompressionPreset = PhotoCompressionPreset.presets[0]
}

@Observable
@MainActor
final class PhotoCompressionViewModel {
    var photos: [PhotoItem] = []
    var isLoading = true
    private(set) var hasLoadedPhotos = false
    var selectedIds: Set<String> = []
    var isCompressing = false
    var errorMessage: String?
    var insufficientDiskSpace = false
    var isDeleting = false
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
        get { AppPreferences.defaultPhotoCompressionPresetID() }
        set { AppPreferences.saveDefaultPhotoCompressionPresetID(newValue) }
    }

    private let photoService = PhotoLibraryService.shared
    private let compressionService: PhotoCompressionService

    init() {
        compressionService = PhotoCompressionService(photoService: photoService)
    }

    var defaultPreset: PhotoCompressionPreset {
        PhotoCompressionPreset.presets.first { $0.id == defaultPresetId } ?? PhotoCompressionPreset.presets[0]
    }

    /// Cached sort ORDER (ids only, C13 parity with ScreenshotCleanerViewModel):
    /// `sortedPhotos` used to re-sort on every access, and progress ticks +
    /// `body` touch it repeatedly. Sort keys are immutable (`fileSize`), so the
    /// order is recomputed only when the id set changes. Items are always
    /// mapped from the current `photos`, so preset/state edits never render
    /// stale copies.
    private var cachedSortedPhotoOrder: [String] = []
    private var cachedSortedPhotoIdSet: Set<String> = []

    var sortedPhotos: [PhotoItem] {
        let ids = Set(photos.map(\.id))
        if ids != cachedSortedPhotoIdSet {
            cachedSortedPhotoOrder = photos.sorted { $0.asset.fileSize > $1.asset.fileSize }.map(\.id)
            cachedSortedPhotoIdSet = ids
        }
        let byId = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return cachedSortedPhotoOrder.compactMap { byId[$0] }
    }

    var selectedSize: Int64 {
        photos.totalFileSize(selectedIds: selectedIds, idOf: \.id, sizeOf: { $0.asset.fileSize })
    }

    /// Every eligible photo from the last fetch; `photos` is this list after
    /// the candidate filter.
    private var allPhotoAssets: [AssetSummary] = []
    /// New copies this tool (or video / Live Photo conversion) already made.
    /// Compressing a copy again only loses quality, so they are never listed.
    private var compressedCopyIds: Set<String> = []

    /// Off: only photos over 2 MB that are not HEIC (the ones that shrink).
    var showAllPhotos = false {
        didSet { applyFilter() }
    }

    /// True when the candidate filter hides photos that exist. Set in
    /// `applyFilter`, so a render never re-scans the whole library.
    private(set) var filterHidesPhotos = false

    nonisolated static func candidates(
        from assets: [AssetSummary],
        excluding compressedCopies: Set<String>,
        showAll: Bool
    ) -> [AssetSummary] {
        assets.filter { asset in
            // Live Photos have their own tool; re-encoding only their still
            // would silently drop the motion.
            guard !asset.isLivePhoto, !compressedCopies.contains(asset.id) else { return false }
            return showAll
                || (asset.fileSize >= CleanupLibraryRollup.photoCompressionMinBytes && !asset.isHEIC)
        }
    }

    func loadIfNeeded(modelContext: ModelContext) async {
        guard !hasLoadedPhotos else { return }
        isLoading = true
        errorMessage = nil
        await fetch(modelContext: modelContext)
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh spinner.
    func refresh(modelContext: ModelContext) async {
        // Don't replace `photos` out from under an in-flight compression loop —
        // its per-id index lookups would miss and savings/records would be lost.
        guard !isCompressing else { return }
        errorMessage = nil
        await fetch(modelContext: modelContext)
    }

    private func fetch(modelContext: ModelContext) async {
        // Every settled row that still names a copy: completed swaps, and
        // copies the user chose to keep next to the original.
        let records = (try? modelContext.fetch(FetchDescriptor<CompressionRecord>(
            predicate: #Predicate { $0.outcome != "pending" }
        ))) ?? []
        compressedCopyIds = Set(records.compactMap(\.replacementAssetLocalIdentifier))
        allPhotoAssets = await photoService.fetchAllPhotos()
        applyFilter()
        hasLoadedPhotos = true
    }

    /// Drops photos that left the library (deleted, or replaced by a copy)
    /// from the list AND from the last fetch, so toggling the filter can
    /// never bring a deleted original back.
    private func removePhotos(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        photos.removeAll { ids.contains($0.id) }
        allPhotoAssets.removeAll { ids.contains($0.id) }
        updateFilterHidesPhotos()
    }

    private func updateFilterHidesPhotos() {
        filterHidesPhotos = !showAllPhotos
            && photos.count < Self.candidates(from: allPhotoAssets, excluding: compressedCopyIds, showAll: true).count
    }

    /// Rebuilds `photos` from the last fetch. Per-row quality picks and row
    /// states ("Already compressed", failure reasons) survive.
    private func applyFilter() {
        guard !isCompressing else { return }
        let previous = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        photos = Self.candidates(from: allPhotoAssets, excluding: compressedCopyIds, showAll: showAllPhotos)
            .map { asset in
                var item = PhotoItem(id: asset.id, asset: asset, selectedPreset: previous[asset.id]?.selectedPreset ?? defaultPreset)
                if let state = previous[asset.id]?.compressionState { item.compressionState = state }
                return item
            }
        selectedIds.formIntersection(photos.map(\.id))
        updateFilterHidesPhotos()
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    var allSelected: Bool {
        !photos.isEmpty && selectedIds.count == photos.count
    }

    func selectAll() {
        selectedIds = Set(photos.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    /// The bottom-bar quality picker: one choice for every selected photo.
    func setPresetForSelected(_ preset: PhotoCompressionPreset) {
        for index in photos.indices where selectedIds.contains(photos[index].id) {
            photos[index].selectedPreset = preset
        }
    }

    /// The shared preset of the selection, or nil when it is mixed.
    var selectedPreset: PhotoCompressionPreset? {
        let ids = Set(photos.filter { selectedIds.contains($0.id) }.map(\.selectedPreset.id))
        guard ids.count == 1, let id = ids.first else { return nil }
        return PhotoCompressionPreset.presets.first { $0.id == id }
    }

    func setPreset(_ preset: PhotoCompressionPreset, for photoId: String) {
        if let index = photos.firstIndex(where: { $0.id == photoId }) {
            photos[index].selectedPreset = preset
        }
    }

    /// Conservative synchronous savings estimate for the row hint: scale the
    /// original by quality and, when downscaling, by the area ratio.
    func estimateSize(for photo: PhotoItem) -> Int64 {
        var factor = Double(photo.selectedPreset.quality)
        if let maxDim = photo.selectedPreset.maxDimension {
            let longest = Double(max(photo.asset.pixelWidth, photo.asset.pixelHeight))
            if longest > Double(maxDim) {
                let scale = Double(maxDim) / longest
                factor *= scale * scale
            }
        }
        return Int64(Double(photo.asset.fileSize) * min(factor, 1.0))
    }

    func deletePhoto(id: String) async -> Bool {
        guard !isDeleting, !isCompressing else { return !photos.contains(where: { $0.id == id }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: [id])
            removePhotos([id])
            selectedIds.remove(id)
        } catch {
            errorMessage = error.localizedDescription
        }
        return !photos.contains(where: { $0.id == id })
    }

    /// Starts the batch on a VM-owned task so the screen can cancel it on
    /// disappear (COMP-08). Idempotent while a batch is running.
    func startBatchCompression(modelContext: ModelContext) {
        guard batchTask == nil else { return }
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
            removePhotos(done)
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
            for index in photos.indices where ids.contains(photos[index].id) {
                if keptIds.contains(photos[index].id) {
                    photos[index].compressionState = .keptOriginal(reason: "Original kept — both versions in your library")
                } else {
                    photos[index].compressionState = .waiting
                }
            }
            isCompressing = false
        }
    }

    func compressSelected(modelContext: ModelContext) async {
        guard !selectedIds.isEmpty, !isCompressing, !isDeleting else { return }
        errorMessage = nil
        batchSummary = nil

        // Re-encoding needs scratch space for the temp file; keep parity with the
        // video tool's headroom check.
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

        // D1: resolve leftovers from any interrupted swap BEFORE the batch.
        await CompressionJournal.reconcile(modelContext: modelContext)

        // COMP-12: deterministic batch order (descending file size, id tiebreak)
        // matching the on-screen list instead of nondeterministic Set iteration.
        // Owned by CompressionBatchRunner.run; the VM only builds the inputs.
        let fileSizes = photos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }

        // O(1) row lookup for the batch: `refresh()` and per-item delete are
        // both no-ops while `isCompressing`, so no structural mutation can
        // reorder rows mid-batch and these indices stay valid until the
        // terminal removeAll below.
        let indexById = Dictionary(uniqueKeysWithValues: photos.enumerated().map { ($1.id, $0) })

        let handlers = CompressionBatchRunner.Handlers(
            setExporting: { [weak self] index, progress in
                guard let self else { return }
                self.photos[index].compressionState = .exporting(progress)
            },
            setKeptOriginal: { [weak self] index, reason in
                guard let self else { return }
                self.photos[index].compressionState = .keptOriginal(reason: reason)
            },
            setCompleted: { [weak self] index, saved in
                guard let self else { return }
                self.photos[index].compressionState = .completed(savedBytes: saved)
            },
            setFailed: { [weak self] index, message in
                guard let self else { return }
                self.photos[index].compressionState = .failed(message)
            },
            setWaiting: { [weak self] index in
                guard let self else { return }
                self.photos[index].compressionState = .waiting
            },
            setCopySaved: { [weak self] index in
                guard let self else { return }
                self.photos[index].compressionState = .copySaved
            },
            setPhase: { [weak self] phase in
                self?.phase = phase
            }
        )

        let isSizeUnknown: @MainActor @Sendable (Error) -> Bool = { error in
            guard let compressionError = error as? PhotoCompressionError else { return false }
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
                let preset = self.photos[index].selectedPreset
                let originalSize = self.photos[index].asset.fileSize
                // D1: journal the swap before it starts (see VideoCompressionViewModel).
                // Throws when the pending row is not durable — that aborts this
                // item before any library write (no journal, no swap).
                let swap = try CompressionSwap(
                    mediaType: .photo,
                    assetId: id,
                    originalSize: originalSize,
                    exportPreset: preset.id,
                    modelContext: modelContext
                )
                do {
                    let compressResult = try await self.compressionService.compressPhoto(
                        assetId: id,
                        preset: preset,
                        // D1: the library write is about to start — from here a crash
                        // could strand a copy whose id the journal never learned.
                        onSaveWillCommit: {
                            swap.markSaveAttempted()
                        },
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
                        self.photos[index].compressionState = .keptOriginal(reason: "No savings — kept original")
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
                        // A cancel is not a failure: History must not render a red
                        // badge for something the batch summary reports as cancelled.
                        await swap.markSkipped(assetId: id)
                        throw error
                    }
                    if let compressionError = error as? PhotoCompressionError,
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
        removePhotos(successfulIds)
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
