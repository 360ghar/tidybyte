import AVFoundation
import CryptoKit
import Photos
import UIKit

enum SwipeFilter: Sendable, Hashable {
    case allMedia
    case allMediaBefore(date: Date)
    case notInAnyAlbum
    case specificAlbum(id: String)
    case notSwipedYet
    case screenshots
    case customAssetIds(Set<String>)
}

actor PhotoLibraryService {

    /// Single app-wide instance (A11). Every view/view model used to construct
    /// its own service, each owning a private `PHCachingImageManager` — that
    /// fragmented the image cache across instances and multiplied actors.
    /// One instance means one shared prefetch cache.
    static let shared = PhotoLibraryService()

    /// Upper bound for any single PhotoKit image/data request so a stalled
    /// iCloud download can't hang the awaiting task indefinitely.
    private static let requestTimeoutSeconds: TimeInterval = 20

    private let imageManager = PHCachingImageManager()
    private var changeObserverHelper: PhotoLibraryChangeObserverHelper?

    /// Baseline for incremental change details (SHARED-08): the broadest
    /// recent fetch result, so `handleLibraryChange` can evict exactly the
    /// removed/changed asset ids instead of purging the whole image cache.
    /// `PHFetchResult` is a lazy snapshot — retaining it is cheap.
    private var changeBaselineFetch: PHFetchResult<PHAsset>?

    // Called when the photo library changes — consumers can listen via this callback
    private var onLibraryChange: (@Sendable () -> Void)?

    init() {
        imageManager.allowsCachingHighQualityImages = true
    }

    deinit {
        // Ensure we never leave a dangling change observer registered with the
        // shared photo library if the service is deallocated.
        if let helper = changeObserverHelper {
            PHPhotoLibrary.shared().unregisterChangeObserver(helper)
        }
    }

    // MARK: - Change Observation

    func startObservingChanges(onChange: @escaping @Sendable () -> Void) {
        guard changeObserverHelper == nil else { return }
        self.onLibraryChange = onChange
        let helper = PhotoLibraryChangeObserverHelper { [weak self] box in
            Task { [weak self] in
                await self?.handleLibraryChange(box.change)
            }
        }
        self.changeObserverHelper = helper
        PHPhotoLibrary.shared().register(helper)
    }

    /// Keeps `ImageCache` coherent with the library (SHARED-08): evicts
    /// exactly the assets PhotoKit reports as removed or changed, so an
    /// in-app delete of N photos no longer re-decodes the other ~200 cached
    /// thumbnails. Falls back to a full purge when incremental details are
    /// unavailable (fetch result released, non-incremental change) — stale
    /// thumbnails are worse than re-decode churn.
    private func handleLibraryChange(_ change: PHChange) async {
        if let baseline = changeBaselineFetch,
           let details = change.changeDetails(for: baseline),
           details.hasIncrementalChanges {
            // Advance the baseline so the NEXT change diffs against current
            // state rather than re-reporting these same objects.
            changeBaselineFetch = details.fetchResultAfterChanges
            let removedIds = details.removedObjects.map(\.localIdentifier)
            let changedIds = details.changedObjects.map(\.localIdentifier)
            for id in removedIds + changedIds {
                await ImageCache.shared.removeImage(for: id)
                await ImageCache.shared.removeImage(for: "\(id)#degraded")
            }
        } else {
            await ImageCache.shared.removeAll()
        }
        onLibraryChange?()
    }

    /// Records a fetch result as the change-details baseline. Keeps the
    /// broadest recent fetch: narrow fetches (a preview sheet's handful of
    /// ids, the screenshots-only census) must not displace a full-library
    /// snapshot, or deletions outside their membership would go unreported
    /// and leave stale thumbnails behind. Called from the `extractSummaries`
    /// funnel so every census-style fetch participates.
    private func retainChangeBaseline(_ fetchResult: PHFetchResult<PHAsset>) {
        if let current = changeBaselineFetch, current.count > fetchResult.count { return }
        changeBaselineFetch = fetchResult
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
        for index in 0..<smartAlbums.count {
            let collection = smartAlbums.object(at: index)
            // Single fetch per album: newest-first ordering gives both the
            // count and the thumbnail id (previously two fetches per album).
            let (count, thumbnailId) = Self.countAndNewestId(in: collection)
            // Smart albums with zero assets are system noise ("Recently
            // Added" before any import, etc.) — still skipped. User albums
            // below are kept even when empty: a newly created album must be
            // visible in the pickers or it can never receive anything (A6).
            guard count > 0 else { continue }
            albums.append(AlbumInfo(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                count: count,
                type: .smartAlbum,
                thumbnailAssetId: thumbnailId
            ))
        }

        // User-created albums — including empty ones.
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        for index in 0..<userAlbums.count {
            let collection = userAlbums.object(at: index)
            let (count, thumbnailId) = Self.countAndNewestId(in: collection)
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

    /// One PhotoKit fetch per album returning both the asset count and the
    /// newest asset's id (for thumbnails).
    nonisolated private static func countAndNewestId(in collection: PHAssetCollection) -> (Int, String?) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(in: collection, options: options)
        return (fetched.count, fetched.firstObject?.localIdentifier)
    }

    // MARK: - Asset Fetching

    func fetchAssets(filter: SwipeFilter) -> [AssetSummary] {
        switch filter {
        case .allMedia:
            let fetchResult = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            return extractSummaries(from: fetchResult)

        case .allMediaBefore(let cutoffDate):
            // Same options (and therefore ordering) as All Media, narrowed to
            // media created on or before the user's chosen starting position.
            let options = allAssetsFetchOptions()
            options.predicate = NSPredicate(format: "creationDate <= %@", cutoffDate as NSDate)
            let fetchResult = PHAsset.fetchAssets(with: options)
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
            // Swipe history lives in SwiftData, not PhotoKit — the session view
            // model filters it out after the fetch.
            let fetchResult = PHAsset.fetchAssets(with: allAssetsFetchOptions())
            return extractSummaries(from: fetchResult)

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

    /// Groups burst frames by `burstIdentifier` alone and drops single-frame
    /// "bursts". Apple's docs are ambiguous about whether `representsBurst` is
    /// set on every frame (vs. only the representative), so requiring it made
    /// the tool silently empty on some devices (LF-03). Frames are sorted by
    /// creation date within each group.
    func fetchBurstPhotos() -> [String: [AssetSummary]] {
        let allAssets = PHAsset.fetchAssets(with: allAssetsFetchOptions())

        var groups: [String: [AssetSummary]] = [:]
        for index in 0..<allAssets.count {
            let asset = allAssets.object(at: index)
            if let burstId = asset.burstIdentifier {
                let summary = Self.makeSummary(from: asset)
                groups[burstId, default: []].append(summary)
            }
        }
        for key in groups.keys {
            groups[key]?.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
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
        await loadThumbnailWithQuality(for: assetId, size: size).image
    }

    /// `PHAsset` overload so scan loops can resolve a whole batch with one
    /// `phAssetsById` fetch instead of one identifier lookup per image.
    func loadThumbnail(for asset: PHAsset, size: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        await loadThumbnailWithQuality(for: asset, size: size).image
    }

    /// E4 (residual SHARED-05): reports whether the returned thumbnail is the
    /// DEGRADED fast-format placeholder (asset not on this device). Callers
    /// caching results key degraded images separately so a sharp version
    /// fetched later (after iCloud download) replaces the soft one instead of
    /// being blocked by it for the whole session.
    func loadThumbnailWithQuality(for assetId: String, size: CGSize = CGSize(width: 200, height: 200)) async -> (image: UIImage?, isDegraded: Bool) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return (nil, false)
        }
        return await loadThumbnailWithQuality(for: asset, size: size)
    }

    func loadThumbnailWithQuality(for asset: PHAsset, size: CGSize = CGSize(width: 200, height: 200)) async -> (image: UIImage?, isDegraded: Bool) {
        await requestImageWithQuality(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            deliveryMode: .fastFormat,
            // Preserve the original loadThumbnail behavior exactly (.none):
            // .fast can crop when aspect-filling.
            resizeMode: .none,
            allowsNetworkAccess: true
        )
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
        return await loadAnalysisImage(for: asset, targetSize: targetSize)
    }

    /// `PHAsset` overload so scan loops can resolve a whole batch with one
    /// `phAssetsById` fetch instead of one identifier lookup per image.
    func loadAnalysisImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await requestImage(
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
        await requestImageWithQuality(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            deliveryMode: deliveryMode,
            resizeMode: resizeMode,
            allowsNetworkAccess: allowsNetworkAccess
        ).image
    }

    /// `requestImage` plus the degraded flag (E4). A `.fastFormat` request for
    /// an iCloud-optimized asset delivers exactly one callback, flagged
    /// degraded — that soft placeholder is the terminal result and is reported
    /// as such so callers can cache it under a degraded key.
    private func requestImageWithQuality(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode,
        allowsNetworkAccess: Bool
    ) async -> (image: UIImage?, isDegraded: Bool) {
        let box = QualityResultBox()

        await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer<Bool>(continuation)

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
                resumer.resume(false)
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
                if isDegraded { box.isDegraded = true }
                if let image = image { box.image = image }

                if info?[PHImageErrorKey] != nil {
                    AppLog.photo.error("Image request failed: \(String(describing: info?[PHImageErrorKey]), privacy: .public)")
                    resumer.resume(isDegraded)
                } else if isCancelled {
                    resumer.resume(isDegraded)
                } else if !isDegraded {
                    resumer.resume(false)
                } else if deliveryMode == .fastFormat {
                    // .fastFormat delivers exactly one callback; for iCloud-optimized
                    // assets that single result is flagged degraded. No non-degraded
                    // result is coming, so the degraded image IS the terminal result.
                    resumer.resume(true)
                } else if isInCloud && !allowsNetworkAccess {
                    // The full asset lives only in iCloud and network access is
                    // off, so no non-degraded result will ever arrive. Give up
                    // promptly so a scan doesn't stall per iCloud-only photo.
                    // Discard the retained degraded placeholder so the caller
                    // gets nil and falls back to the thumbnail path.
                    box.image = nil
                    resumer.resume(isDegraded)
                }
                // A degraded placeholder without an error (and reachable) means
                // the full-quality result is still coming — keep waiting for it.
            }
        }

        return (box.image, box.isDegraded)
    }

    /// Mutable capture box bridging the PhotoKit completion closure (which may
    /// fire on a PhotoKit queue) into the quality tuple returned on the actor.
    private final class QualityResultBox: @unchecked Sendable {
        var image: UIImage?
        var isDegraded = false
    }

    // MARK: - Album Membership

    /// Local identifiers of the user albums that currently contain the asset.
    /// Used to restore album membership when an asset is replaced (e.g. after
    /// video compression or Live Photo conversion).
    func userAlbumIdentifiers(containing assetId: String) -> [String] {
        userAlbumIdentifiers(for: [assetId])[assetId] ?? []
    }

    /// Album membership for a batch of assets in a single pass over user
    /// albums (one fetch per album instead of one predicate fetch per
    /// album per item). Batch loops should call this once before iterating.
    func userAlbumIdentifiers(for assetIds: Set<String>) -> [String: [String]] {
        guard !assetIds.isEmpty else { return [:] }
        var result: [String: [String]] = Dictionary(uniqueKeysWithValues: assetIds.map { ($0, [String]()) })
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let fetched = PHAsset.fetchAssets(in: collection, options: nil)
            var memberIds = Set<String>()
            fetched.enumerateObjects { asset, _, _ in
                if assetIds.contains(asset.localIdentifier) {
                    memberIds.insert(asset.localIdentifier)
                }
            }
            for id in memberIds {
                result[id, default: []].append(collection.localIdentifier)
            }
        }
        return result
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

    /// Deletes the given assets atomically. If the batch fails (e.g. one
    /// protected/undeletable asset aborts the whole `performChanges`), retries
    /// each identifier individually so the deletable ones still go through,
    /// then throws `partialDeletion` carrying the identifiers that DID succeed,
    /// so callers can drop them from their lists instead of showing ghosts
    /// (SHARED-01).
    @discardableResult
    func deleteAssets(identifiers: [String]) async throws -> Set<String> {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            // fetchAssets silently drops externally-vanished ids, so intersect
            // with what was actually fetched — callers sum freed bytes over
            // returned ids, and crediting vanished ids would inflate the ledger.
            var fetchedIds = Set<String>()
            assets.enumerateObjects { asset, _, _ in
                fetchedIds.insert(asset.localIdentifier)
            }
            return Set(identifiers).intersection(fetchedIds)
        } catch {
            var succeeded = Set<String>()
            var failed = 0
            for (offset, id) in identifiers.enumerated() {
                // Serial by design (PhotoKit-safe); yield periodically so a
                // long fallback retry stays cancellable and responsive.
                if offset % 10 == 0 { await Task.yield() }
                if Task.isCancelled { throw CancellationError() }
                do {
                    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                        // The asset no longer exists in the library (deleted
                        // externally — e.g. iCloud sync or the Photos app —
                        // between fetch and delete). The delete's goal state,
                        // "not in the library", is already satisfied, so
                        // deliberately report it in the succeeded set instead
                        // of scaring the user with a bogus "couldn't be
                        // deleted" failure.
                        succeeded.insert(id)
                        continue
                    }
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.deleteAssets([asset] as NSArray)
                    }
                    succeeded.insert(id)
                } catch {
                    failed += 1
                }
            }
            if failed > 0 {
                throw PhotoServiceError.partialDeletion(succeededIds: succeeded, failedCount: failed)
            }
            // Every individual retry succeeded — the batch failure was
            // transient; nothing remains.
            return succeeded
        }
    }

    func addToAlbum(assetIdentifiers: [String], albumIdentifier: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else {
            throw PhotoServiceError.albumNotFound
        }

        var changeRequestCreated = false
        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.addAssets(assets)
            changeRequestCreated = true
        }
        // The album fetched fine but PhotoKit refused to build a change request
        // for it — a distinct failure from the album being missing (SHARED-02).
        guard changeRequestCreated else {
            throw PhotoServiceError.albumChangeFailed
        }
    }

    func removeFromAlbum(assetIdentifiers: [String], albumIdentifier: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else {
            throw PhotoServiceError.albumNotFound
        }

        var changeRequestCreated = false
        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.removeAssets(assets)
            changeRequestCreated = true
        }
        // Same distinction as addToAlbum: the album exists but PhotoKit refused
        // to build a change request for it (SHARED-02).
        guard changeRequestCreated else {
            throw PhotoServiceError.albumChangeFailed
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
        return await sha256ForPrimaryResource(of: asset)
    }

    /// `PHAsset` overload so duplicate scans can resolve a whole batch with
    /// one `phAssetsById` fetch instead of one identifier lookup per asset.
    func sha256ForPrimaryResource(of asset: PHAsset) async -> String? {
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

    /// Resolves a batch of identifiers with ONE PhotoKit fetch. Scan loops
    /// that load an image (or hash) per asset must use this + the `PHAsset`
    /// loader overloads instead of the per-id loaders — one identifier lookup
    /// per image turned full-library scans into tens of thousands of fetches.
    /// Missing ids (deleted externally mid-scan) are simply absent.
    nonisolated func phAssetsById(_ ids: [String]) -> [String: PHAsset] {
        guard !ids.isEmpty else { return [:] }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byId: [String: PHAsset] = [:]
        byId.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in
            byId[asset.localIdentifier] = asset
        }
        return byId
    }

    /// Loads an image asset's full-resolution encoded data (with EXIF, including
    /// the orientation tag, intact). Used by photo compression to re-encode.
    /// Mirrors `requestImage`'s single-resume / timeout behaviour so a stalled
    /// iCloud download can't hang the caller.
    func loadFullImageData(for assetId: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        return await loadFullImageData(for: asset)
    }

    /// `PHAsset` overload so compression batches can resolve a whole batch
    /// with one `phAssetsById` fetch instead of one identifier lookup per item.
    func loadFullImageData(for asset: PHAsset) async -> Data? {
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

        // One batched resolve for the whole export, not one identifier lookup
        // per file (ids deleted externally mid-export are skipped).
        let assetsById = phAssetsById(identifiers)
        for id in identifiers {
            if Task.isCancelled { break }
            if let asset = assetsById[id],
               let url = await writeResourceToTemp(asset: asset, in: folder) {
                urls.append(url)
            }
            completed += 1
            await onProgress(completed, total)
        }

        return urls
    }

    private func writeResourceToTemp(asset: PHAsset, in folder: URL) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = preferredPrimaryResource(from: resources) else { return nil }

        let fileURL = uniqueURL(for: resource.originalFilename, in: folder)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer<URL?>(continuation)

            // Wire the timeout + cleanup hook BEFORE issuing the request so a
            // synchronously-delivered callback still cancels the timeout Task
            // (otherwise it lingers, orphaned, for requestTimeoutSeconds), and
            // cancel the in-flight write on resume (SHARED-07).
            let resourceManager = PHAssetResourceManager.default()
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
                resumer.resume(nil)
            }
            resumer.onResume = {
                timeoutTask.cancel()
            }

            // `writeData` returns Void (no request ID to cancel), so the timeout
            // task above is the cancellation hook.
            resourceManager.writeData(
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

    nonisolated private static func estimateFileSize(from resources: [PHAssetResource]) -> Int64 {
        var totalSize: Int64 = 0
        for resource in resources {
            totalSize += Self.safeFileSize(for: resource)
        }
        return totalSize
    }

    nonisolated private static func makeSummary(from asset: PHAsset) -> AssetSummary {
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
            fileSize: Self.estimateFileSize(from: resources),
            filename: resources.first?.originalFilename,
            isFavorite: asset.isFavorite,
            isBurst: asset.representsBurst,
            burstIdentifier: asset.burstIdentifier,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLocallyAvailable: isLocal,
            assetOrigin: Self.detectOrigin(for: asset, filename: resources.first?.originalFilename)
        )
    }

    /// Best-effort classification of where an asset came from, used by the Smart
    /// Categories tool. Pure metadata inspection — no image loading. Camera
    /// captures carry a recognizable filename prefix or capture markers (HDR,
    /// depth, Live, GPS); screenshots have the screenshot subtype; anything else
    /// that's an image is treated as likely saved from another app (the category
    /// is intentionally recall-leaning and surfaced to the user as "likely").
    nonisolated private static func detectOrigin(for asset: PHAsset, filename: String?) -> AssetOrigin {
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

    private func extractSummaries(from fetchResult: PHFetchResult<PHAsset>, excluding: Set<String> = [], sort: Bool = true) -> [AssetSummary] {
        retainChangeBaseline(fetchResult)
        return Self.buildSummaries(from: fetchResult, excluding: excluding, sort: sort)
    }

    nonisolated private static func buildSummaries(from fetchResult: PHFetchResult<PHAsset>, excluding: Set<String> = [], sort: Bool = true) -> [AssetSummary] {
        var summaries: [AssetSummary] = []
        summaries.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            if !excluding.contains(asset.localIdentifier) {
                summaries.append(Self.makeSummary(from: asset))
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

    nonisolated private static func safeFileSize(for resource: PHAssetResource) -> Int64 {
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
    case albumChangeFailed
    case partialDeletion(succeededIds: Set<String>, failedCount: Int)

    var errorDescription: String? {
        switch self {
        case .albumNotFound: return "Album not found."
        case .albumCreationFailed: return "Failed to create album."
        case .albumChangeFailed: return "Couldn't modify the album. Please try again."
        case .partialDeletion(let succeededIds, let failedCount):
            let total = succeededIds.count + failedCount
            return "Deleted \(succeededIds.count) of \(total) items. \(failedCount) couldn't be deleted. Try again."
        }
    }

    /// Ids that were deleted before a partial failure. `nil` for non-partial
    /// errors. Shared by all cleanup tools' delete reconciliation (C5).
    var succeededIds: Set<String>? {
        if case .partialDeletion(let succeededIds, _) = self {
            return succeededIds
        }
        return nil
    }
}

// MARK: - Change Observer Helper

/// Carries a `PHChange` from PhotoKit's arbitrary callback queue to the
/// service actor. `PHChange` isn't `Sendable`, but the object is immutable
/// once delivered — Apple's own PhotoKit samples hand it across queues the
/// same way — and the box is unwrapped immediately on the actor, never stored.
/// Internal (not private) so the observer helper's initializer can name it.
struct LibraryChangeBox: @unchecked Sendable {
    let change: PHChange
}

final class PhotoLibraryChangeObserverHelper: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let onChange: @Sendable (LibraryChangeBox) -> Void

    init(onChange: @escaping @Sendable (LibraryChangeBox) -> Void) {
        self.onChange = onChange
        super.init()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange(LibraryChangeBox(change: changeInstance))
    }
}
