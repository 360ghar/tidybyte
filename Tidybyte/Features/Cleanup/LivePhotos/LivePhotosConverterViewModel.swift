import SwiftUI
import Photos

enum ConversionState {
    case idle
    case converting
    case completed
    case failed(String)
}

struct LivePhotoItem: Identifiable {
    let id: String
    let asset: AssetSummary
    var conversionState: ConversionState = .idle
    var savedBytes: Int64 = 0
}

@Observable
@MainActor
final class LivePhotosConverterViewModel {
    var items: [LivePhotoItem] = []
    var isLoading = true
    private(set) var hasLoadedItems = false
    var selectedIds: Set<String> = []
    var isSelectionMode = false
    var convertingAll = false
    var errorMessage: String?
    var totalSavedBytes: Int64 = 0
    var convertedCount: Int = 0

    private let photoService = PhotoLibraryService()

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.asset.fileSize }
    }

    var estimatedSavings: Int64 {
        // Live Photos are roughly 2x the size of stills
        items.reduce(0) { $0 + $1.asset.fileSize / 2 }
    }

    var deletedCount: Int = 0

    func indexOfItem(id: String) -> Int? {
        items.firstIndex(where: { $0.id == id })
    }

    /// Deletes a Live Photo outright (removes both the still and the motion
    /// component) without creating a replacement. Use when the user decides
    /// the Live Photo is junk from the preview. Album membership is dropped
    /// automatically by iOS on delete.
    func deleteLivePhoto(itemId: String) async {
        guard indexOfItem(id: itemId) != nil else { return }
        errorMessage = nil
        do {
            try await photoService.deleteAssets(identifiers: [itemId])
            items.removeAll { $0.id == itemId }
            deletedCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedItems else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let livePhotos = await photoService.fetchLivePhotos()
        items = livePhotos.map { LivePhotoItem(id: $0.id, asset: $0) }
        hasLoadedItems = true
        isLoading = false
    }

    /// Re-fetches Live Photos without toggling `isLoading`, so the existing list
    /// stays visible under the pull-to-refresh spinner instead of flashing the skeleton.
    func refresh() async {
        errorMessage = nil
        let livePhotos = await photoService.fetchLivePhotos()
        items = livePhotos.map { LivePhotoItem(id: $0.id, asset: $0) }
        hasLoadedItems = true
    }

    func convertSingle(itemId: String) async {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        errorMessage = nil
        items[index].conversionState = .converting

        do {
            let savedBytes = try await performConversion(assetId: itemId)
            totalSavedBytes += savedBytes
            convertedCount += 1
            // Re-lookup: the array may have shifted during the await.
            if let idx = items.firstIndex(where: { $0.id == itemId }) {
                items[idx].savedBytes = savedBytes
                items[idx].conversionState = .completed
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == itemId }) {
                items[idx].conversionState = .failed(error.localizedDescription)
            }
            errorMessage = error.localizedDescription
        }
    }

    func convertAll() async {
        errorMessage = nil
        convertingAll = true
        let pendingIds = items.map(\.id)
        for itemId in pendingIds {
            guard let index = items.firstIndex(where: { $0.id == itemId }) else { continue }
            guard case .idle = items[index].conversionState else { continue }
            items[index].conversionState = .converting
            do {
                let savedBytes = try await performConversion(assetId: itemId)
                totalSavedBytes += savedBytes
                convertedCount += 1
                // Re-lookup: the array may have shifted during the await.
                if let idx = items.firstIndex(where: { $0.id == itemId }) {
                    items[idx].savedBytes = savedBytes
                    items[idx].conversionState = .completed
                }
            } catch {
                if let idx = items.firstIndex(where: { $0.id == itemId }) {
                    items[idx].conversionState = .failed(error.localizedDescription)
                }
                errorMessage = error.localizedDescription
            }
        }
        convertingAll = false
    }

    private func performConversion(assetId: String) async throws -> Int64 {
        guard let phAsset = photoService.getPHAsset(for: assetId) else {
            throw LivePhotoError.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: phAsset)
        guard let photoResource = resources.first(where: { $0.type == .photo }) else {
            throw LivePhotoError.noPhotoResource
        }

        let originalSize = resources.reduce(Int64(0)) { total, resource in
            guard resource.responds(to: NSSelectorFromString("fileSize")),
                  let size = resource.value(forKey: "fileSize") as? Int64 else {
                return total
            }
            return total + size
        }

        // Read the still-image resource bytes directly. Writing these bytes back
        // (rather than decoding to a UIImage and re-encoding) preserves the
        // original quality and EXIF metadata.
        let resourceManager = PHAssetResourceManager.default()
        let imageData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let resumer = ThrowingContinuationResumer(continuation)
            var data = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            // Network access is allowed, so a stalled iCloud download could leave
            // the completion handler unfired forever. Bound it with a timeout +
            // request cancellation, wired before the request so even a synchronous
            // callback cancels the timer. Without this the item hangs in `.converting`.
            var requestID: PHAssetResourceDataRequestID = 0
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(30))
                resumer.resume(throwing: LivePhotoError.conversionTimedOut)
            }
            resumer.onResume = {
                resourceManager.cancelDataRequest(requestID)
                timeoutTask.cancel()
            }

            requestID = resourceManager.requestData(
                for: photoResource,
                options: options
            ) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                if let error {
                    resumer.resume(throwing: error)
                } else {
                    resumer.resume(returning: data)
                }
            }
        }

        guard !imageData.isEmpty else {
            throw LivePhotoError.invalidImageData
        }

        // Capture album membership before deleting the original.
        let albumIdentifiers = await photoService.userAlbumIdentifiers(containing: assetId)

        // Save as a new still photo, preserving the original's metadata.
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.originalFilename = photoResource.originalFilename
            request.addResource(with: .photo, data: imageData, options: resourceOptions)
            request.creationDate = phAsset.creationDate
            request.location = phAsset.location
            request.isFavorite = phAsset.isFavorite
            placeholder = request.placeholderForCreatedAsset
        }

        guard let replacementId = placeholder?.localIdentifier else {
            throw LivePhotoError.invalidImageData
        }

        // Restore album membership on the replacement (best effort).
        for albumId in albumIdentifiers {
            do {
                try await photoService.addToAlbum(assetIdentifiers: [replacementId], albumIdentifier: albumId)
            } catch {
                AppLog.photo.error("Failed to restore album \(albumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Delete the original Live Photo only after confirming the new still exists.
        try await photoService.deleteAssets(identifiers: [assetId])

        return max(0, originalSize - Int64(imageData.count))
    }
}

enum LivePhotoError: LocalizedError {
    case assetNotFound
    case noPhotoResource
    case invalidImageData
    case conversionTimedOut

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Live Photo not found."
        case .noPhotoResource: "Could not find still image in Live Photo."
        case .invalidImageData: "Invalid image data."
        case .conversionTimedOut: "Timed out loading the photo (it may still be in iCloud). Please try again."
        }
    }
}
