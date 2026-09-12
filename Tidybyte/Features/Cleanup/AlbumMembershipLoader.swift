import Photos

/// Batches album-membership lookups for the comparison views (DUP-06).
///
/// The previous per-asset lookup pattern cost one fetch per album
/// per asset — O(assets × albums) blocking PhotoKit fetches while the pager
/// renders thumbnails. This helper does a single pass over all user albums,
/// fetching each album's assets once with an `IN` predicate, and accumulates
/// `[assetID: [albumName]]` for exactly the assets the view cares about.
enum AlbumMembershipLoader {
    /// Async wrapper (C14): the multi-query PhotoKit enumeration used to run
    /// synchronously on the main actor inside `.task`, stalling the pager's
    /// first frame for users with many albums. The blocking work now runs on a
    /// background task; only the result assignment hops back to the caller.
    static func membership(for assetIds: Set<String>) async -> [String: [String]] {
        guard !assetIds.isEmpty else { return [:] }
        return await Task.detached(priority: .userInitiated) {
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
        }.value
    }
}
