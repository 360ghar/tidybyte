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
    var totalSaved: Int64 = 0
    /// Per-batch outcome counts, set once the loop finishes so the view can
    /// show a single summary / success haptic (COMP-09, COMP-11).
    var batchSummary: CompressionBatchSummary?
    private(set) var isCancelled = false
    /// The batch mutation loop, owned by the VM so leaving the screen can
    /// cancel it instead of orphaning the mutation loop (COMP-08).
    private var batchTask: Task<Void, Never>?

    var defaultPresetId: String {
        get { AppPreferences.defaultCompressionPresetID() }
        set { AppPreferences.saveDefaultCompressionPresetID(newValue) }
    }

    private let photoService = PhotoLibraryService()
    private let compressionService: VideoCompressionService

    init() {
        compressionService = VideoCompressionService(photoService: photoService)
    }

    var defaultPreset: CompressionPreset {
        CompressionPreset.presets.first { $0.id == defaultPresetId } ?? CompressionPreset.presets[0]
    }

    var sortedVideos: [VideoItem] {
        videos.sorted { $0.asset.fileSize > $1.asset.fileSize }
    }

    var selectedSize: Int64 {
        videos.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.asset.fileSize }
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
        videos = videoAssets.map { VideoItem(id: $0.id, asset: $0, selectedPreset: defaultPreset) }
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

    func setPreset(_ preset: CompressionPreset, for videoId: String) {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            videos[index].selectedPreset = preset
        }
    }

    func estimateSize(for video: VideoItem) -> Int64 {
        // Synchronous estimation based on bitrate * duration
        let bitrate: Int64
        switch video.selectedPreset.id {
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
    func deleteVideo(id: String) async {
        guard !isDeleting, !isCompressing else { return }
        errorMessage = nil
        isDeleting = true
        do {
            try await photoService.deleteAssets(identifiers: [id])
            videos.removeAll { $0.id == id }
            selectedIds.remove(id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
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
    /// save+delete in the services).
    func cancelCompression() {
        isCancelled = true
        batchTask?.cancel()
    }

    func compressSelected(modelContext: ModelContext) async {
        guard !selectedIds.isEmpty, !isCompressing else { return }
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
        totalSaved = 0
        var successfulIds: Set<String> = []
        var completedCount = 0
        var failedCount = 0
        var skippedCount = 0

        // COMP-16: skip assets that already have a completed record so they are
        // never re-encoded (quality degradation).
        let previouslyCompletedIds: Set<String> = ((try? modelContext.fetch(
            FetchDescriptor<CompressionRecord>(predicate: #Predicate { $0.outcome == "completed" })
        )) ?? []).reduce(into: Set<String>()) { $0.insert($1.assetLocalIdentifier) }

        // COMP-12: deterministic batch order (descending file size, id tiebreak)
        // matching the on-screen list instead of nondeterministic Set iteration.
        let orderedIds = sortedBatchIds(
            selected: selectedIds,
            // Idempotent overwrite: PhotoKit identifiers are unique, so a
            // repeated id (shouldn't happen) just re-records the same size
            // instead of trapping the scan.
            fileSizes: videos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }
        )

        for id in orderedIds {
            // COMP-08: cancellation is checked at the top of every iteration.
            if isCancelled { break }
            guard let index = videos.firstIndex(where: { $0.id == id }) else { continue }
            // Captured before the await so the failure audit trail below stays
            // accurate even if the row vanishes from `videos` mid-export.
            let originalSize = videos[index].asset.fileSize
            let selectedPresetId = videos[index].selectedPreset.preset

            if previouslyCompletedIds.contains(id) {
                videos[index].compressionState = .keptOriginal(reason: "Already compressed")
                skippedCount += 1
                continue
            }

            videos[index].compressionState = .exporting(0)

            do {
                // COMP-10: never export with a preset larger than the source.
                let preset = VideoCompressionService.effectivePreset(
                    for: videos[index].asset,
                    selected: videos[index].selectedPreset
                )
                let result = try await compressionService.compressVideo(
                    assetId: id,
                    preset: preset
                ) { [weak self] progress in
                    guard let self else { return }
                    if let idx = self.videos.firstIndex(where: { $0.id == id }) {
                        self.videos[idx].compressionState = .exporting(progress)
                    }
                }

                if result.skipped {
                    // COMP-04: no-savings items stay in the list with an
                    // explanation instead of silently vanishing.
                    skippedCount += 1
                    if let updatedIndex = videos.firstIndex(where: { $0.id == id }) {
                        videos[updatedIndex].compressionState = .keptOriginal(reason: "No savings — kept original")
                    }
                    let record = CompressionRecord(
                        assetLocalIdentifier: id,
                        replacementAssetLocalIdentifier: nil,
                        originalSizeBytes: result.originalSize,
                        compressedSizeBytes: result.originalSize,
                        exportPreset: preset.preset,
                        outcome: "skipped"
                    )
                    modelContext.insert(record)
                    do {
                        try modelContext.save()
                    } catch {
                        AppLog.data.error("Failed to save compression record: \(error.localizedDescription, privacy: .public)")
                    }
                    continue
                }

                // Record the outcome unconditionally. The original was already
                // deleted inside compressVideo, so the savings + record must be
                // captured even if `videos` was mutated during the await; the UI
                // state update below is best-effort.
                let saved = max(0, result.originalSize - result.compressedSize)
                totalSaved += saved
                completedCount += 1
                successfulIds.insert(id)
                if let updatedIndex = videos.firstIndex(where: { $0.id == id }) {
                    videos[updatedIndex].compressionState = .completed(savedBytes: saved)
                }

                // Save compression record
                let record = CompressionRecord(
                    assetLocalIdentifier: id,
                    replacementAssetLocalIdentifier: result.replacementAssetIdentifier,
                    originalSizeBytes: result.originalSize,
                    compressedSizeBytes: result.compressedSize,
                    exportPreset: preset.preset,
                    outcome: "completed"
                )
                modelContext.insert(record)
                do {
                    try modelContext.save()
                } catch {
                    AppLog.data.error("Failed to save compression record: \(error.localizedDescription, privacy: .public)")
                }

            } catch CompressionError.cancelled {
                // User cancelled mid-item: nothing was replaced; reset the row
                // and stop the loop.
                if let idx = videos.firstIndex(where: { $0.id == id }) {
                    videos[idx].compressionState = .waiting
                }
                break
            } catch CompressionError.sizeUnknown {
                // COMP-07: iCloud-only / unknown size — leave the original alone.
                skippedCount += 1
                if let idx = videos.firstIndex(where: { $0.id == id }) {
                    videos[idx].compressionState = .keptOriginal(reason: "Size unknown (iCloud-only) — skipped")
                }
                continue
            } catch {
                failedCount += 1
                if let idx = videos.firstIndex(where: { $0.id == id }) {
                    videos[idx].compressionState = .failed(error.localizedDescription)
                }

                // Keep an audit trail of failed compressions too. Uses the
                // values captured before the export so a vanished row can't
                // degrade the record into a neutral "No savings" row.
                let failed = CompressionRecord(
                    assetLocalIdentifier: id,
                    replacementAssetLocalIdentifier: nil,
                    originalSizeBytes: originalSize,
                    compressedSizeBytes: 0,
                    exportPreset: selectedPresetId,
                    outcome: "failed"
                )
                modelContext.insert(failed)
                try? modelContext.save()
            }
        }

        // COMP-04: remove only successfully compressed (and deleted) items;
        // skipped ones stay so the user can see why they were left alone.
        videos.removeAll { successfulIds.contains($0.id) }
        selectedIds.subtract(successfulIds)
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
