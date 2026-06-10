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

    func compressSelected(modelContext: ModelContext) async {
        guard !selectedIds.isEmpty, !isCompressing else { return }

        // Re-encoding needs scratch space for the temp file; keep parity with the
        // video tool's headroom check.
        let totalSelectedSize = selectedSize
        if let freeSpace = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           freeSpace < Int64(Double(totalSelectedSize) * 2.0) {
            insufficientDiskSpace = true
            return
        }

        isCompressing = true
        totalSaved = 0
        var successfulIds: Set<String> = []

        for id in Array(selectedIds) {
            guard let index = photos.firstIndex(where: { $0.id == id }) else { continue }
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

                // Record the outcome unconditionally. The original was already
                // deleted inside compressPhoto, so the savings + record must be
                // captured even if `photos` was mutated during the await; the UI
                // state update below is best-effort.
                let saved = result.skipped ? 0 : max(0, result.originalSize - result.compressedSize)
                totalSaved += saved
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
                    outcome: result.skipped ? "skipped" : "completed",
                    mediaType: "photo"
                )
                modelContext.insert(record)
                do {
                    try modelContext.save()
                } catch {
                    AppLog.data.error("Failed to save compression record: \(error.localizedDescription, privacy: .public)")
                }
            } catch {
                if let idx = photos.firstIndex(where: { $0.id == id }) {
                    photos[idx].compressionState = .failed(error.localizedDescription)
                }
                errorMessage = error.localizedDescription

                let failed = CompressionRecord(
                    assetLocalIdentifier: id,
                    replacementAssetLocalIdentifier: nil,
                    originalSizeBytes: photos.first(where: { $0.id == id })?.asset.fileSize ?? 0,
                    compressedSizeBytes: 0,
                    exportPreset: preset.id,
                    outcome: "failed",
                    mediaType: "photo"
                )
                modelContext.insert(failed)
                try? modelContext.save()
            }
        }

        photos.removeAll { successfulIds.contains($0.id) }
        selectedIds.subtract(successfulIds)
        isCompressing = false
    }
}
