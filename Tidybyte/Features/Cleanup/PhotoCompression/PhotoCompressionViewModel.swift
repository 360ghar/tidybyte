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
    var totalSaved: Int64 = 0
    var insufficientDiskSpace = false
    var isDeleting = false
    /// Per-batch outcome counts, set once the loop finishes so the view can
    /// show a single summary / success haptic (COMP-09, COMP-11).
    var batchSummary: CompressionBatchSummary?
    private(set) var isCancelled = false
    /// The batch mutation loop, owned by the VM so leaving the screen can
    /// cancel it instead of orphaning the mutation loop (COMP-08).
    private var batchTask: Task<Void, Never>?

    var defaultPresetId: String {
        get { AppPreferences.defaultPhotoCompressionPresetID() }
        set { AppPreferences.saveDefaultPhotoCompressionPresetID(newValue) }
    }

    private let photoService = PhotoLibraryService()
    private let compressionService: PhotoCompressionService

    init() {
        compressionService = PhotoCompressionService(photoService: photoService)
    }

    var defaultPreset: PhotoCompressionPreset {
        PhotoCompressionPreset.presets.first { $0.id == defaultPresetId } ?? PhotoCompressionPreset.presets[0]
    }

    var sortedPhotos: [PhotoItem] {
        photos.sorted { $0.asset.fileSize > $1.asset.fileSize }
    }

    var selectedSize: Int64 {
        photos.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.asset.fileSize }
    }

    func loadIfNeeded() async {
        guard !hasLoadedPhotos else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        // Live Photos have their own tool; re-encoding only their still would
        // silently drop the motion component, so exclude them here.
        let photoAssets = await photoService.fetchAllPhotos().filter { !$0.isLivePhoto }
        photos = photoAssets.map { PhotoItem(id: $0.id, asset: $0, selectedPreset: defaultPreset) }
        hasLoadedPhotos = true
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh spinner.
    func refresh() async {
        // Don't replace `photos` out from under an in-flight compression loop —
        // its per-id index lookups would miss and savings/records would be lost.
        guard !isCompressing else { return }
        errorMessage = nil
        let photoAssets = await photoService.fetchAllPhotos().filter { !$0.isLivePhoto }
        photos = photoAssets.map { PhotoItem(id: $0.id, asset: $0, selectedPreset: defaultPreset) }
        hasLoadedPhotos = true
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

    func deletePhoto(id: String) async {
        guard !isDeleting, !isCompressing else { return }
        errorMessage = nil
        isDeleting = true
        do {
            try await photoService.deleteAssets(identifiers: [id])
            photos.removeAll { $0.id == id }
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
            fileSizes: photos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }
        )

        for id in orderedIds {
            // COMP-08: cancellation is checked at the top of every iteration.
            if isCancelled { break }
            guard let index = photos.firstIndex(where: { $0.id == id }) else { continue }
            // Captured before the await so the failure audit trail below stays
            // accurate even if the row vanishes from `photos` mid-export.
            let originalSize = photos[index].asset.fileSize

            if previouslyCompletedIds.contains(id) {
                photos[index].compressionState = .keptOriginal(reason: "Already compressed")
                skippedCount += 1
                continue
            }

            photos[index].compressionState = .exporting(0)
            let preset = photos[index].selectedPreset

            do {
                let result = try await compressionService.compressPhoto(
                    assetId: id,
                    preset: preset
                ) { [weak self] progress in
                    guard let self else { return }
                    if let idx = self.photos.firstIndex(where: { $0.id == id }) {
                        self.photos[idx].compressionState = .exporting(progress)
                    }
                }

                if result.skipped {
                    // COMP-04: no-savings items stay in the list with an
                    // explanation instead of silently vanishing.
                    skippedCount += 1
                    if let updatedIndex = photos.firstIndex(where: { $0.id == id }) {
                        photos[updatedIndex].compressionState = .keptOriginal(reason: "No savings — kept original")
                    }
                    let record = CompressionRecord(
                        assetLocalIdentifier: id,
                        replacementAssetLocalIdentifier: nil,
                        originalSizeBytes: result.originalSize,
                        compressedSizeBytes: result.originalSize,
                        exportPreset: preset.id,
                        outcome: "skipped",
                        mediaType: "photo"
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
                // deleted inside compressPhoto, so the savings + record must be
                // captured even if `photos` was mutated during the await; the UI
                // state update below is best-effort.
                let saved = max(0, result.originalSize - result.compressedSize)
                totalSaved += saved
                completedCount += 1
                successfulIds.insert(id)
                if let updatedIndex = photos.firstIndex(where: { $0.id == id }) {
                    photos[updatedIndex].compressionState = .completed(savedBytes: saved)
                }

                let record = CompressionRecord(
                    assetLocalIdentifier: id,
                    replacementAssetLocalIdentifier: result.replacementAssetIdentifier,
                    originalSizeBytes: result.originalSize,
                    compressedSizeBytes: result.compressedSize,
                    exportPreset: preset.id,
                    outcome: "completed",
                    mediaType: "photo"
                )
                modelContext.insert(record)
                do {
                    try modelContext.save()
                } catch {
                    AppLog.data.error("Failed to save compression record: \(error.localizedDescription, privacy: .public)")
                }
            } catch PhotoCompressionError.cancelled {
                // User cancelled mid-item: nothing was replaced; reset the row
                // and stop the loop.
                if let idx = photos.firstIndex(where: { $0.id == id }) {
                    photos[idx].compressionState = .waiting
                }
                break
            } catch PhotoCompressionError.sizeUnknown {
                // COMP-07: iCloud-only / unknown size — leave the original alone.
                skippedCount += 1
                if let idx = photos.firstIndex(where: { $0.id == id }) {
                    photos[idx].compressionState = .keptOriginal(reason: "Size unknown (iCloud-only) — skipped")
                }
                continue
            } catch {
                failedCount += 1
                if let idx = photos.firstIndex(where: { $0.id == id }) {
                    photos[idx].compressionState = .failed(error.localizedDescription)
                }

                // Uses the size captured before the export so a vanished row
                // can't degrade the record into a neutral "No savings" row.
                let failed = CompressionRecord(
                    assetLocalIdentifier: id,
                    replacementAssetLocalIdentifier: nil,
                    originalSizeBytes: originalSize,
                    compressedSizeBytes: 0,
                    exportPreset: preset.id,
                    outcome: "failed",
                    mediaType: "photo"
                )
                modelContext.insert(failed)
                try? modelContext.save()
            }
        }

        // COMP-04: remove only successfully compressed (and deleted) items;
        // skipped ones stay so the user can see why they were left alone.
        photos.removeAll { successfulIds.contains($0.id) }
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
