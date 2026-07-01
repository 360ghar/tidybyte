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

    func compressSelected(modelContext: ModelContext) async {
        guard !selectedIds.isEmpty, !isCompressing else { return }
        errorMessage = nil

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
        totalSaved = 0
        var successfulIds: Set<String> = []

        for id in Array(selectedIds) {
            guard let index = videos.firstIndex(where: { $0.id == id }) else { continue }
            videos[index].compressionState = .exporting(0)

            do {
                let preset = videos[index].selectedPreset
                let result = try await compressionService.compressVideo(
                    assetId: id,
                    preset: preset
                ) { [weak self] progress in
                    guard let self else { return }
                    if let idx = self.videos.firstIndex(where: { $0.id == id }) {
                        self.videos[idx].compressionState = .exporting(progress)
                    }
                }

                // Record the outcome unconditionally. The original was already
                // deleted inside compressVideo, so the savings + record must be
                // captured even if `videos` was mutated during the await; the UI
                // state update below is best-effort.
                let saved = result.skipped ? 0 : max(0, result.originalSize - result.compressedSize)
                totalSaved += saved
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
                    outcome: result.skipped ? "skipped" : "completed"
                )
                modelContext.insert(record)
                do {
                    try modelContext.save()
                } catch {
                    AppLog.data.error("Failed to save compression record: \(error.localizedDescription, privacy: .public)")
                }

            } catch {
                if let idx = videos.firstIndex(where: { $0.id == id }) {
                    videos[idx].compressionState = .failed(error.localizedDescription)
                }
                errorMessage = error.localizedDescription

                // Keep an audit trail of failed compressions too.
                let failed = CompressionRecord(
                    assetLocalIdentifier: id,
                    replacementAssetLocalIdentifier: nil,
                    originalSizeBytes: videos.first(where: { $0.id == id })?.asset.fileSize ?? 0,
                    compressedSizeBytes: 0,
                    exportPreset: videos.first(where: { $0.id == id })?.selectedPreset.preset ?? "",
                    outcome: "failed"
                )
                modelContext.insert(failed)
                try? modelContext.save()
            }
        }

        // Remove successfully compressed videos and clear only their IDs
        videos.removeAll { successfulIds.contains($0.id) }
        selectedIds.subtract(successfulIds)
        isCompressing = false
    }
}
