import AVFoundation
import CryptoKit
import Photos
import UIKit

enum SwipeFilter: Sendable, Hashable {
    case allMedia
    case notInAnyAlbum
    case specificAlbum(id: String)
    case notSwipedYet
    case screenshots
    case customAssetIds(Set<String>)
}

actor PhotoLibraryService {

    /// Upper bound for any single PhotoKit image/data request so a stalled
    /// iCloud download can't hang the awaiting task indefinitely.
    private static let requestTimeoutSeconds: TimeInterval = 20

    private let imageManager = PHCachingImageManager()
    private var changeObserverHelper: PhotoLibraryChangeObserverHelper?

    // Called when the photo library changes — consumers can listen via this callback
    private var onLibraryChange: (@Sendable () -> Void)?

    init() {
        imageManager.allowsCachingHighQualityImages = true
    }

    deinit {
        // Ensure we never leave a dangling change observer registered with the
        // shared photo library if the service is deallocated without an explicit
        // stopObservingChanges() call.
        if let helper = changeObserverHelper {
            PHPhotoLibrary.shared().unregisterChangeObserver(helper)
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Change Observation

    func startObservingChanges(onChange: @escaping @Sendable () -> Void) {
        self.onLibraryChange = onChange
        let helper = PhotoLibraryChangeObserverHelper { [weak self] in
            Task { [weak self] in
                await self?.handleLibraryChange()
            }
        }
        self.changeObserverHelper = helper
        PHPhotoLibrary.shared().register(helper)
    }

    func stopObservingChanges() {
        if let helper = changeObserverHelper {
            PHPhotoLibrary.shared().unregisterChangeObserver(helper)
            changeObserverHelper = nil
        }
        onLibraryChange = nil
    }

    private func handleLibraryChange() {
        onLibraryChange?()
    }

    // MARK: - Album Fetching

    func fetchUserAlbums() -> [AlbumInfo] {
        var albums: [AlbumInfo] = []

        // Smart albums (Favorites, Recents, etc.)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            let thumbnailId = self.firstThumbnailId(in: collection)
            albums.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                count: count,
                type: .smartAlbum,
                thumbnailAssetId: thumbnailId
            ))
        }

        // User-created albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            let thumbnailId = self.firstThumbnailId(in: collection)
            albums.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                count: count,
                type: .userAlbum,
                thumbnailAssetId: thumbnailId
            ))
        }

        // Smart albums first, then user albums, both sorted alphabetically
        let smart = albums.filter { $0.type == .smartAlbum }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let user = albums.filter { $0.type == .userAlbum }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return smart + user
    }

    nonisolated private func firstThumbnailId(in collection: PHAssetCollection) -> String? {
        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: options).firstObject?.localIdentifier
    }

    // MARK: - Asset Fetching

    func fetchAssets(filter: SwipeFilter, swipedIdentifiers: Set<String> = []) -> [AssetSummary] {
        switch filter {
        case .allMedia:
            let fetchResult = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            return extractSummaries(from: fetchResult)

        case .notInAnyAlbum:
            let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            let assetsInAlbums = collectAssetsInUserAlbums()
            return extractSummaries(from: allAssets, excluding: assetsInAlbums)

        case .specificAlbum(let albumId):
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject else {
                return []
            }
            let fetchResult = PHAsset.fetchAssets(in: collection, options: allAssetsFetchOptions())
            return extractSummaries(from: fetchResult)

        case .notSwipedYet:
            let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            return extractSummaries(from: allAssets, excluding: swipedIdentifiers)

        case .screenshots:
            let options = allAssetsFetchOptions()
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: options)
            return extractSummaries(from: fetchResult)

        case .customAssetIds(let ids):
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
            return extractSummaries(from: assets)
        }
    }

    func fetchAssetsByMediaType(_ mediaType: PHAssetMediaType) -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", mediaType.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    func fetchScreenshots() -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    func fetchLivePhotos() -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    func fetchBurstPhotos() -> [String: [AssetSummary]] {
        let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())

        var groups: [String: [AssetSummary]] = [:]
        allAssets.enumerateObjects { asset, _, _ in
            if asset.representsBurst, let burstId = asset.burstIdentifier {
                let summary = self.makeSummary(from: asset)
                groups[burstId, default: []].append(summary)
            }
        }
        return groups.filter { $0.value.count > 1 }
    }

    func fetchAllPhotos() -> [AssetSummary] {
        let options = allAssetsFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return extractSummaries(from: result)
    }

    // MARK: - Image Loading

    func loadImage(for assetId: String, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await loadImage(for: asset, targetSize: targetSize, contentMode: contentMode)
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        await requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, deliveryMode: .highQualityFormat)
    }

    func loadThumbnail(for assetId: String, size: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await requestImage(for: asset, targetSize: size, contentMode: .aspectFill, deliveryMode: .fastFormat)
    }

    /// Loads a sharp, deterministically-sized image for on-device analysis
    /// (blur/exposure). Uses high-quality delivery + exact resize so sharpness
    /// isn't corrupted by a soft fast-format thumbnail, and disables network
    /// access so a full-library scan never stalls downloading from iCloud —
    /// callers should fall back to `loadThumbnail` when this returns `nil` (the
    /// asset's full resolution lives only in iCloud).
    func loadAnalysisImage(for assetId: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            deliveryMode: .highQualityFormat,
            resizeMode: .exact,
            allowsNetworkAccess: false
        )
    }

    /// Loads a `PHLivePhoto` representation of a Live Photo asset for in-app
    /// motion playback (e.g. `PHLivePhotoView`). Mirrors `requestImage`'s
    /// single-resume/timeout/degraded-result-guard behaviour: it always resumes
    /// on the terminal callback and falls back to `nil` after
    /// `requestTimeoutSeconds` so a stalled iCloud download cannot hang callers.
    func loadLivePhoto(for assetId: String, targetSize: CGSize) async -> PHLivePhoto? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject,
              asset.mediaSubtypes.contains(.photoLive) else {
            return nil
        }
        return await requestLivePhoto(for: asset, targetSize: targetSize)
    }

    /// Loads a playable `AVPlayerItem` for a video asset (e.g. for `VideoPlayer`
    /// / `AVPlayer`). Mirrors `requestLivePhoto`'s single-resume/timeout
    /// behaviour. The non-`Sendable` `AVPlayerItem` is returned inside an
    /// `UncheckedSendableBox` so it can safely cross from this actor to the
    /// `@MainActor` caller that builds the player; the caller unwraps `.value`.
    func loadPlayerItem(for assetId: String) async -> UncheckedSendableBox<AVPlayerItem>? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject,
              asset.mediaType == .video else {
            return nil
        }
        return await requestPlayerItem(for: asset)
    }

    private func requestPlayerItem(for asset: PHAsset) async -> UncheckedSendableBox<AVPlayerItem>? {
        await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer<UncheckedSendableBox<AVPlayerItem>?>(continuation)

            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true

            // Wire the timeout + cleanup hook BEFORE issuing the request so a
            // synchronously-delivered callback still cancels the timeout Task
            // (otherwise it lingers, orphaned, for requestTimeoutSeconds).
            let manager = imageManager
            var requestID: PHImageRequestID = PHInvalidImageRequestID
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                resumer.resume(nil)
            }
            resumer.onResume = {
                manager.cancelImageRequest(requestID)
                timeoutTask.cancel()
            }

            requestID = imageManager.requestPlayerItem(forVideo: asset, options: options) { item, info in
                if let error = info?[PHImageErrorKey] {
                    AppLog.photo.error("Player item request failed: \(String(describing: error), privacy: .public)")
                }
                resumer.resume(item.map(UncheckedSendableBox.init))
            }
        }
    }

    private func requestLivePhoto(
        for asset: PHAsset,
        targetSize: CGSize
    ) async -> PHLivePhoto? {
        await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer(continuation)

            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            // Wire the timeout + cleanup hook BEFORE issuing the request so a
            // synchronously-delivered callback still cancels the timeout Task
            // (otherwise it lingers, orphaned, for requestTimeoutSeconds).
            let manager = imageManager
            var requestID: PHImageRequestID = PHInvalidImageRequestID
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                resumer.resume(nil)
            }
            resumer.onResume = {
                manager.cancelImageRequest(requestID)
                timeoutTask.cancel()
            }

            requestID = imageManager.requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { livePhoto, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if let error = info?[PHImageErrorKey] {
                    AppLog.photo.error("Live Photo request failed: \(String(describing: error), privacy: .public)")
                    resumer.resume(livePhoto)
                } else if isCancelled {
                    resumer.resume(livePhoto)
                } else if !isDegraded {
                    resumer.resume(livePhoto)
                }
                // A degraded result without an error means the full-quality Live
                // Photo is still coming — keep waiting. Unlike `requestImage`,
                // network access is always allowed here, so there is no
                // "no result will ever arrive" case to short-circuit; the
                // `requestTimeoutSeconds` fallback is the only backstop for a
                // stalled iCloud download. Do NOT copy `requestImage`'s
                // `isInCloud && !allowsNetworkAccess` give-up branch — it can
                // never fire on this path and would be dead code.
            }
        }
    }

    /// Loads an image via `PHImageManager`, resuming exactly once on the terminal
    /// callback (final image, error, or cancellation) and falling back to `nil`
    /// after a timeout. Without this, an asset that only ever delivers a degraded
    /// placeholder (e.g. an iCloud asset with no network) would hang the caller
    /// forever, since the previous implementation only resumed on a non-degraded
    /// result.
    private func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode = .none,
        allowsNetworkAccess: Bool = true
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer(continuation)

            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.isNetworkAccessAllowed = allowsNetworkAccess
            options.isSynchronous = false
            options.resizeMode = resizeMode

            // Wire the timeout + cleanup hook BEFORE issuing the request so a
            // synchronously-delivered callback still cancels the timeout Task
            // (otherwise it lingers, orphaned, for requestTimeoutSeconds).
            let manager = imageManager
            var requestID: PHImageRequestID = PHInvalidImageRequestID
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                resumer.resume(nil)
            }
            resumer.onResume = {
                manager.cancelImageRequest(requestID)
                timeoutTask.cancel()
            }

            requestID = imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if let error = info?[PHImageErrorKey] {
                    AppLog.photo.error("Image request failed: \(String(describing: error), privacy: .public)")
                    resumer.resume(image)
                } else if isCancelled {
                    resumer.resume(image)
                } else if !isDegraded {
                    resumer.resume(image)
                } else if deliveryMode == .fastFormat {
                    // .fastFormat delivers exactly one callback; for iCloud-optimized
                    // assets that single result is flagged degraded. No non-degraded
                    // result is coming, so the degraded image IS the terminal result —
                    // resume with it rather than waiting out the timeout (which would
                    // yield nil → a gray placeholder for the thumbnail).
                    resumer.resume(image)
                } else if isInCloud && !allowsNetworkAccess {
                    // The full asset lives only in iCloud and network access is
                    // off, so no non-degraded result will ever arrive. Give up
                    // promptly (rather than waiting out the timeout) so a scan
                    // doesn't stall per iCloud-only photo; the caller falls back.
                    resumer.resume(nil)
                }
                // A degraded placeholder without an error (and reachable) means
                // the full-quality result is still coming — keep waiting for it.
            }
        }
    }

    // MARK: - Album Membership

    func albumsContaining(assetId: String) -> [String] {
        guard PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject != nil else {
            return []
        }
        var albumNames: [String] = []
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "localIdentifier = %@", assetId)
            let count = PHAsset.fetchAssets(in: collection, options: opts).count
            if count > 0 {
                albumNames.append(collection.localizedTitle ?? "Untitled")
            }
        }
        return albumNames
    }

    /// Local identifiers of the user albums that currently contain the asset.
    /// Used to restore album membership when an asset is replaced (e.g. after
    /// video compression or Live Photo conversion).
    func userAlbumIdentifiers(containing assetId: String) -> [String] {
        var ids: [String] = []
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "localIdentifier = %@", assetId)
            if PHAsset.fetchAssets(in: collection, options: opts).count > 0 {
                ids.append(collection.localIdentifier)
            }
        }
        return ids
    }

    /// Local identifiers of every asset in at least one user-created album,
    /// computed in a single pass. The swipe session uses this to skip the
    /// "Add to Album" prompt for photos that are already organized.
    func assetIdentifiersInUserAlbums() -> Set<String> {
        collectAssetsInUserAlbums()
    }

    // MARK: - Pre-fetching

    func startCaching(assetIds: [String], targetSize: CGSize) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var phAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            phAssets.append(asset)
        }
        imageManager.startCachingImages(for: phAssets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCaching(assetIds: [String], targetSize: CGSize) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var phAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            phAssets.append(asset)
        }
        imageManager.stopCachingImages(for: phAssets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopAllCaching() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - Mutations

    func deleteAssets(identifiers: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    func addToAlbum(assetIdentifiers: [String], albumIdentifier: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else {
            throw PhotoServiceError.albumNotFound
        }

        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.addAssets(assets)
        }
    }

    func removeFromAlbum(assetIdentifiers: [String], albumIdentifier: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else {
            throw PhotoServiceError.albumNotFound
        }

        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.removeAssets(assets)
        }
    }

    func createAlbum(name: String) async throws -> String {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let id = placeholder?.localIdentifier else {
            throw PhotoServiceError.albumCreationFailed
        }
        return id
    }

    // MARK: - Asset Data

    /// Streams an asset's primary resource through a SHA-256 hasher in chunks and
    /// returns the lowercased hex digest. Unlike loading the full `Data` and then
    /// hashing it, this keeps only one chunk in memory at a time — essential for
    /// large videos, which could otherwise exhaust memory during duplicate scans.
    func sha256ForPrimaryResource(of assetId: String) async -> String? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = preferredPrimaryResource(from: resources) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer<String?>(continuation)
            var hasher = SHA256()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            // Mirror loadFullImageData: bound the request with a timeout + cancellation
            // (wired before the request) so a stalled iCloud resource can't hang the
            // whole duplicate scan, which calls this once per asset.
            let resourceManager = PHAssetResourceManager.default()
            var requestID: PHAssetResourceDataRequestID = 0
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                resumer.resume(nil)
            }
            resumer.onResume = {
                resourceManager.cancelDataRequest(requestID)
                timeoutTask.cancel()
            }

            requestID = resourceManager.requestData(
                for: resource,
                options: options
            ) { chunk in
                hasher.update(data: chunk)
            } completionHandler: { error in
                if let error {
                    AppLog.photo.error("Resource hash failed: \(error.localizedDescription, privacy: .public)")
                    resumer.resume(nil)
                } else {
                    let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    resumer.resume(hex)
                }
            }
        }
    }

    nonisolated func getPHAsset(for identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    /// Loads an image asset's full-resolution encoded data (with EXIF, including
    /// the orientation tag, intact). Used by photo compression to re-encode.
    /// Mirrors `requestImage`'s single-resume / timeout behaviour so a stalled
    /// iCloud download can't hang the caller.
    func loadFullImageData(for assetId: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer<Data?>(continuation)

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            // Wire the timeout + cleanup hook BEFORE issuing the request so a
            // synchronously-delivered callback still cancels the timeout Task
            // (otherwise it lingers, orphaned, for requestTimeoutSeconds).
            let manager = imageManager
            var requestID: PHImageRequestID = PHInvalidImageRequestID
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                resumer.resume(nil)
            }
            resumer.onResume = {
                manager.cancelImageRequest(requestID)
                timeoutTask.cancel()
            }

            requestID = imageManager.requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if let error = info?[PHImageErrorKey] {
                    AppLog.photo.error("Image data request failed: \(String(describing: error), privacy: .public)")
                    resumer.resume(nil)
                } else {
                    resumer.resume(data)
                }
            }
        }
    }

    /// Writes full-resolution representations of the given assets to temporary
    /// files (under one share-export folder) so they can be handed to a share
    /// sheet. Streams the primary resource bytes directly — preserving the
    /// original quality and metadata, no re-encode — and reports
    /// `(completed, total)` after each file. iCloud assets respect the per-item
    /// timeout; failures are skipped.
    func exportAssetsForSharing(
        identifiers: [String],
        onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareExport-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var urls: [URL] = []
        let total = identifiers.count
        var completed = 0

        for id in identifiers {
            if Task.isCancelled { break }
            if let url = await writeResourceToTemp(assetId: id, in: folder) {
                urls.append(url)
            }
            completed += 1
            await onProgress(completed, total)
        }

        return urls
    }

    private func writeResourceToTemp(assetId: String, in folder: URL) async -> URL? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = preferredPrimaryResource(from: resources) else { return nil }

        let fileURL = uniqueURL(for: resource.originalFilename, in: folder)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer<URL?>(continuation)
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: fileURL,
                options: options
            ) { error in
                if let error {
                    AppLog.photo.error("Share export write failed: \(error.localizedDescription, privacy: .public)")
                    resumer.resume(nil)
                } else {
                    resumer.resume(fileURL)
                }
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                resumer.resume(nil)
            }
            resumer.onResume = { timeoutTask.cancel() }
        }
    }

    /// A non-colliding URL inside `folder` for `filename`, appending `-2`, `-3`…
    /// before the extension when needed (two assets can share an original name).
    nonisolated private func uniqueURL(for filename: String, in folder: URL) -> URL {
        let name = filename.isEmpty ? "media.dat" : filename
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = folder.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    // MARK: - Helpers

    nonisolated private func allAssetsFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        return options
    }

    nonisolated private func estimateFileSize(from resources: [PHAssetResource]) -> Int64 {
        var totalSize: Int64 = 0
        for resource in resources {
            totalSize += safeFileSize(for: resource)
        }
        return totalSize
    }

    nonisolated private func makeSummary(from asset: PHAsset) -> AssetSummary {
        let resources = PHAssetResource.assetResources(for: asset)
        let isLocal = resources.allSatisfy { resource in
            guard resource.responds(to: NSSelectorFromString("locallyAvailable")) else { return true }
            return (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
        }

        let mediaType: MediaType
        switch asset.mediaType {
        case .image:
            mediaType = .photo
        case .video:
            mediaType = .video
        case .audio:
            mediaType = .audio
        default:
            mediaType = .unknown
        }

        return AssetSummary(
            id: asset.localIdentifier,
            mediaType: mediaType,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            fileSize: estimateFileSize(from: resources),
            filename: resources.first?.originalFilename,
            isFavorite: asset.isFavorite,
            isBurst: asset.representsBurst,
            burstIdentifier: asset.burstIdentifier,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLocallyAvailable: isLocal,
            assetOrigin: detectOrigin(for: asset, filename: resources.first?.originalFilename)
        )
    }

    /// Best-effort classification of where an asset came from, used by the Smart
    /// Categories tool. Pure metadata inspection — no image loading. Camera
    /// captures carry a recognizable filename prefix or capture markers (HDR,
    /// depth, Live, GPS); screenshots have the screenshot subtype; anything else
    /// that's an image is treated as likely saved from another app (the category
    /// is intentionally recall-leaning and surfaced to the user as "likely").
    nonisolated private func detectOrigin(for asset: PHAsset, filename: String?) -> AssetOrigin {
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return .screenshot
        }

        let name = (filename ?? "").uppercased()
        let cameraPrefixes = ["IMG_", "DSC", "DSCF", "DJI_", "GOPR", "PXL_", "MVIMG"]
        let isCameraName = cameraPrefixes.contains { name.hasPrefix($0) } || name.hasSuffix(".DNG")
        let hasCameraMarkers = asset.mediaSubtypes.contains(.photoHDR)
            || asset.mediaSubtypes.contains(.photoDepthEffect)
            || asset.mediaSubtypes.contains(.photoLive)
            || asset.location != nil
        if isCameraName || hasCameraMarkers {
            return .camera
        }

        let foreignMarkers = ["WA", "FB_IMG", "RECEIVED_", "DOWNLOAD", "IMG-", "INSTA", "TELEGRAM", "SNAPCHAT"]
        if foreignMarkers.contains(where: { name.contains($0) }) {
            return .savedFromApp
        }

        // Images that match neither a camera nor screenshot signature are most
        // likely imported/downloaded; videos without markers stay unknown.
        return asset.mediaType == .image ? .savedFromApp : .unknown
    }

    nonisolated private func extractSummaries(from fetchResult: PHFetchResult<PHAsset>, excluding: Set<String> = [], sort: Bool = true) -> [AssetSummary] {
        var summaries: [AssetSummary] = []
        summaries.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            if !excluding.contains(asset.localIdentifier) {
                summaries.append(self.makeSummary(from: asset))
            }
        }
        if sort {
            summaries.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
        return summaries
    }

    nonisolated private func collectAssetsInUserAlbums() -> Set<String> {
        var inAlbum = Set<String>()
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                inAlbum.insert(asset.localIdentifier)
            }
        }
        return inAlbum
    }

    nonisolated private func preferredPrimaryResource(from resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first { $0.type == .fullSizePhoto }
        ?? resources.first { $0.type == .photo }
        ?? resources.first { $0.type == .fullSizeVideo }
        ?? resources.first { $0.type == .video }
        ?? resources.first { $0.type == .audio }
        ?? resources.first
    }

    nonisolated private func safeFileSize(for resource: PHAssetResource) -> Int64 {
        guard resource.responds(to: NSSelectorFromString("fileSize")),
              let size = resource.value(forKey: "fileSize") as? Int64 else {
            return 0
        }
        return size
    }
}

// MARK: - Errors

enum PhotoServiceError: LocalizedError {
    case albumNotFound
    case albumCreationFailed
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .albumNotFound: "Album not found."
        case .albumCreationFailed: "Failed to create album."
        case .unauthorized: "Photo library access not authorized."
        }
    }
}

// MARK: - Change Observer Helper

final class PhotoLibraryChangeObserverHelper: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
