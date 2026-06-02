import AVFoundation
import Photos
import UIKit

struct CompressionPreset: Identifiable, Sendable {
    let id: String
    let label: String
    let preset: String
    let description: String

    static let presets: [CompressionPreset] = [
        CompressionPreset(id: "1080p", label: "1080p HD", preset: AVAssetExportPreset1920x1080, description: "Good quality, moderate savings"),
        CompressionPreset(id: "720p", label: "720p", preset: AVAssetExportPreset1280x720, description: "Decent quality, major savings"),
        CompressionPreset(id: "480p", label: "480p", preset: AVAssetExportPreset640x480, description: "Lower quality, maximum savings")
    ]
}

struct CompressionProgress: Sendable {
    let assetId: String
    let progress: Float
    let state: CompressionState
}

struct CompressionResult: Sendable {
    let originalSize: Int64
    let compressedSize: Int64
    let replacementAssetIdentifier: String?
    /// True when compression would not have saved space, so the original was
    /// left untouched and no replacement was created.
    let skipped: Bool
}

enum CompressionState: Sendable {
    case waiting
    case exporting(Float)
    case saving
    case completed(savedBytes: Int64)
    case failed(String)
}

actor VideoCompressionService {
    private let photoService: PhotoLibraryService

    init(photoService: PhotoLibraryService) {
        self.photoService = photoService
    }

    // MARK: - Estimate Compressed Size

    func estimateCompressedSize(for asset: AssetSummary, preset: CompressionPreset) -> Int64 {
        // Rough estimation based on target bitrate and duration
        let bitrate: Int64
        switch preset.id {
        case "1080p": bitrate = 8_000_000  // 8 Mbps
        case "720p": bitrate = 4_000_000   // 4 Mbps
        case "480p": bitrate = 2_000_000   // 2 Mbps
        default: bitrate = 6_000_000
        }

        let estimatedBytes = (bitrate / 8) * Int64(max(asset.duration, 1))
        return estimatedBytes
    }

    // MARK: - Compress Video

    func compressVideo(
        assetId: String,
        preset: CompressionPreset,
        onProgress: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws -> CompressionResult {
        guard let phAsset = photoService.getPHAsset(for: assetId) else {
            throw CompressionError.assetNotFound
        }

        let avAsset = try await loadAVAsset(from: phAsset)
        let originalSize = getFileSize(for: phAsset)

        // Export to a temp file; guarantee it is removed on every exit path.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset.preset) else {
            throw CompressionError.exportSessionCreationFailed
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Poll progress on a background-priority task that is always cancelled on scope exit.
        // AVAssetExportSession isn't Sendable, but reading `.progress` while the export
        // runs is the documented, thread-safe polling pattern (pre-iOS 18). Box it so the
        // capture across the isolation boundary is explicit rather than an unchecked leak.
        let sessionBox = UncheckedSendableBox(exportSession)
        let progressTask = Task(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await onProgress(sessionBox.value.progress)
            }
        }
        defer { progressTask.cancel() }

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw CompressionError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        }

        // Verify the exported file exists and is non-empty before trusting it.
        let compressedSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            compressedSize = (attrs[.size] as? Int64) ?? 0
        } catch {
            throw CompressionError.fileSizeReadFailed
        }
        guard compressedSize > 0 else {
            throw CompressionError.exportFailed("Exported file was empty.")
        }

        // If compression wouldn't actually save space, keep the original untouched.
        guard compressedSize < originalSize else {
            AppLog.compression.info("No savings compressing \(assetId, privacy: .public); keeping original")
            return CompressionResult(
                originalSize: originalSize,
                compressedSize: originalSize,
                replacementAssetIdentifier: nil,
                skipped: true
            )
        }

        // Capture album membership before deleting the original so we can restore it.
        let albumIdentifiers = await photoService.userAlbumIdentifiers(containing: assetId)

        // Save the compressed video, preserving the original's date/location/favorite.
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            request?.creationDate = phAsset.creationDate
            request?.location = phAsset.location
            request?.isFavorite = phAsset.isFavorite
            placeholder = request?.placeholderForCreatedAsset
        }

        guard let replacementId = placeholder?.localIdentifier else {
            throw CompressionError.exportFailed("Failed to save compressed video to library.")
        }

        // Restore album membership on the replacement (best effort).
        for albumId in albumIdentifiers {
            do {
                try await photoService.addToAlbum(assetIdentifiers: [replacementId], albumIdentifier: albumId)
            } catch {
                AppLog.photo.error("Failed to restore album \(albumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Delete the original only after confirming the replacement exists.
        try await photoService.deleteAssets(identifiers: [assetId])

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: compressedSize,
            replacementAssetIdentifier: replacementId,
            skipped: false
        )
    }

    // MARK: - Helpers

    private func loadAVAsset(from phAsset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            nonisolated(unsafe) var hasResumed = false
            PHImageManager.default().requestAVAsset(
                forVideo: phAsset,
                options: options
            ) { avAsset, _, info in
                guard !hasResumed else { return }
                hasResumed = true
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: CompressionError.videoLoadFailed)
                }
            }
        }
    }

    private func getFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        var total: Int64 = 0
        for resource in resources {
            if resource.responds(to: NSSelectorFromString("fileSize")),
               let size = resource.value(forKey: "fileSize") as? Int64 {
                total += size
            }
        }
        return total
    }
}

enum CompressionError: LocalizedError {
    case assetNotFound
    case videoLoadFailed
    case exportSessionCreationFailed
    case exportFailed(String)
    case fileSizeReadFailed

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Video not found."
        case .videoLoadFailed: "Failed to load video."
        case .exportSessionCreationFailed: "Failed to create export session."
        case .exportFailed(let msg): "Export failed: \(msg)"
        case .fileSizeReadFailed: "Failed to read file size."
        }
    }
}
