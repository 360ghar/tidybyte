import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

struct PhotoCompressionPreset: Identifiable, Sendable {
    let id: String
    let label: String
    /// Longest-edge cap in pixels; `nil` re-encodes at full resolution.
    let maxDimension: CGFloat?
    /// HEIC lossy quality, 0...1.
    let quality: CGFloat
    let description: String

    static let presets: [PhotoCompressionPreset] = [
        PhotoCompressionPreset(id: "high", label: "High Quality", maxDimension: nil, quality: 0.8,
                               description: "Re-encode to HEIC, full resolution"),
        PhotoCompressionPreset(id: "balanced", label: "Balanced", maxDimension: 3024, quality: 0.6,
                               description: "Resize to 3K, good savings"),
        PhotoCompressionPreset(id: "space", label: "Space Saver", maxDimension: 2048, quality: 0.5,
                               description: "Resize to 2K, maximum savings")
    ]
}

/// Re-encodes photos to HEIC (optionally downscaling) to reclaim space, then
/// replaces the original in the library. Mirrors `VideoCompressionService`:
/// reuses its media-agnostic `CompressionResult`/`CompressionState`, writes to a
/// temp file with guaranteed cleanup, skips when no space is saved, preserves
/// date/location/favorite + album membership, and deletes the original last.
actor PhotoCompressionService {
    private let photoService: PhotoLibraryService

    init(photoService: PhotoLibraryService) {
        self.photoService = photoService
    }

    func compressPhoto(
        assetId: String,
        preset: PhotoCompressionPreset,
        onProgress: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws -> CompressionResult {
        guard let phAsset = photoService.getPHAsset(for: assetId) else {
            throw PhotoCompressionError.assetNotFound
        }
        guard phAsset.mediaType == .image, !phAsset.mediaSubtypes.contains(.photoLive) else {
            throw PhotoCompressionError.notAnImage
        }

        await onProgress(0.05)
        let resources = PHAssetResource.assetResources(for: phAsset)
        let originalSize = fileSize(of: resources)

        guard let imageData = await photoService.loadFullImageData(for: assetId) else {
            throw PhotoCompressionError.imageDataLoadFailed
        }
        await onProgress(0.4)

        // Encode to a temp HEIC; guarantee removal on every exit path.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("heic")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try encodeHEIC(
            from: imageData,
            to: tempURL,
            maxDimension: preset.maxDimension,
            quality: preset.quality
        )
        await onProgress(0.8)

        let compressedSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            compressedSize = (attrs[.size] as? Int64) ?? 0
        } catch {
            throw PhotoCompressionError.fileSizeReadFailed
        }
        guard compressedSize > 0 else {
            throw PhotoCompressionError.encodeFailed
        }

        // If re-encoding wouldn't save space (e.g. an already-efficient HEIC),
        // keep the original untouched.
        guard compressedSize < originalSize else {
            AppLog.compression.info("No savings compressing photo \(assetId, privacy: .public); keeping original")
            return CompressionResult(
                originalSize: originalSize,
                compressedSize: originalSize,
                replacementAssetIdentifier: nil,
                skipped: true
            )
        }

        let albumIdentifiers = await photoService.userAlbumIdentifiers(containing: assetId)
        let replacementFilename = heicFilename(from: resources.first?.originalFilename)

        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.originalFilename = replacementFilename
            request.addResource(with: .photo, fileURL: tempURL, options: resourceOptions)
            request.creationDate = phAsset.creationDate
            request.location = phAsset.location
            request.isFavorite = phAsset.isFavorite
            placeholder = request.placeholderForCreatedAsset
        }

        guard let replacementId = placeholder?.localIdentifier else {
            throw PhotoCompressionError.saveFailed("Failed to save compressed photo to library.")
        }
        await onProgress(1.0)

        for albumId in albumIdentifiers {
            try? await photoService.addToAlbum(assetIdentifiers: [replacementId], albumIdentifier: albumId)
        }

        try await photoService.deleteAssets(identifiers: [assetId])

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: compressedSize,
            replacementAssetIdentifier: replacementId,
            skipped: false
        )
    }

    // MARK: - Encoding

    /// Decodes `data`, optionally downscales to `maxDimension` (longest edge),
    /// and writes a HEIC file at `quality`. The thumbnail transform bakes
    /// orientation into the pixels, so the output is always upright. We
    /// deliberately do NOT copy the source's EXIF/TIFF dictionaries: their
    /// embedded Orientation tag would conflict with the already-upright pixels
    /// (causing a double-rotation in viewers that honor it), and their pixel
    /// dimensions would be stale after a downscale. The user-visible metadata
    /// (creation date, location, favorite) is restored on the new asset by the
    /// caller via `PHAssetCreationRequest`, so nothing important is lost.
    private func encodeHEIC(
        from data: Data,
        to url: URL,
        maxDimension: CGFloat?,
        quality: CGFloat
    ) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoCompressionError.encodeFailed
        }

        var thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        // Only cap the longest edge for the downscaling presets. The full-resolution
        // preset (maxDimension == nil) deliberately omits kCGImageSourceThumbnailMaxPixelSize
        // so the image is re-encoded at its true decoded size. Deriving a cap from
        // PHAsset.pixelWidth/Height would silently downscale assets (e.g. RAW/DNG)
        // whose reported dimensions are smaller than the actual decoded image — and the
        // original is deleted afterward, so that loss would be unrecoverable.
        if let maxDimension {
            thumbOptions[kCGImageSourceThumbnailMaxPixelSize] = Int(maxDimension)
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw PhotoCompressionError.encodeFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoCompressionError.encodeFailed
        }

        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoCompressionError.encodeFailed
        }
    }

    // MARK: - Helpers

    private func fileSize(of resources: [PHAssetResource]) -> Int64 {
        var total: Int64 = 0
        for resource in resources {
            if resource.responds(to: NSSelectorFromString("fileSize")),
               let size = resource.value(forKey: "fileSize") as? Int64 {
                total += size
            }
        }
        return total
    }

    private func heicFilename(from original: String?) -> String {
        guard let original, !original.isEmpty else { return "compressed.heic" }
        return ((original as NSString).deletingPathExtension as NSString)
            .appendingPathExtension("heic") ?? "compressed.heic"
    }
}

enum PhotoCompressionError: LocalizedError {
    case assetNotFound
    case notAnImage
    case imageDataLoadFailed
    case encodeFailed
    case fileSizeReadFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Photo not found."
        case .notAnImage: "This item can't be compressed as a photo."
        case .imageDataLoadFailed: "Failed to load the photo."
        case .encodeFailed: "Failed to re-encode the photo."
        case .fileSizeReadFailed: "Failed to read file size."
        case .saveFailed(let msg): "Save failed: \(msg)"
        }
    }
}
