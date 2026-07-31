import Photos

/// Batches album-membership lookups for the comparison views (DUP-06).
///
/// The previous per-asset `albumsContaining` pattern cost one fetch per album
/// per asset — O(assets × albums) blocking PhotoKit fetches while the pager
/// renders thumbnails. This helper does a single pass over all user albums,
/// fetching each album's assets once with an `IN` predicate, and accumulates
/// `[assetID: [albumName]]` for exactly the assets the view cares about.
enum AlbumMembershipLoader {
    static func membership(for assetIds: Set<String>) -> [String: [String]] {
        guard !assetIds.isEmpty else { return [:] }
        var result: [String: [String]] = [:]
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", assetIds)
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            assets.enumerateObjects { asset, _, _ in
                result[asset.localIdentifier, default: []]
                    .append(collection.localizedTitle ?? "Untitled")
            }
        }
        return result
    }
}
