import Photos

/// Batches album-membership lookups for the comparison views (DUP-06).
///
/// The previous per-asset lookup pattern cost one fetch per album
/// per asset — O(assets × albums) blocking PhotoKit fetches while the pager
/// renders thumbnails. This helper does a single pass over all user albums,
/// fetching each album's assets once with an `IN` predicate, and accumulates
/// `[assetID: [albumName]]` for exactly the assets the view cares about.
enum AlbumMembershipLoader {
    /// Async worker (C14): the multi-query PhotoKit enumeration used to run
    /// synchronously on the main actor inside `.task`, stalling the pager's
    /// first frame for users with many albums. The blocking work now runs as a
    /// structured child of the caller's task — cancellable via
    /// `Task.isCancelled` checks — and only the result assignment hops back to
    /// the caller.
    static func membership(for assetIds: Set<String>) async -> [String: [String]] {
        guard !assetIds.isEmpty else { return [:] }
        // Structured concurrency: a child of the caller's task (the pager's
        // `.task`, a `ScanRunner` run), so cancel propagates. The previous
        // `Task.detached` was unstructured and kept PhotoKit queries running
        // after cancel. Checks sit between album fetches and inside enumeration.
        var result: [String: [String]] = [:]
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        for index in 0..<userAlbums.count {
            if Task.isCancelled { return result }
            let collection = userAlbums.object(at: index)
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", assetIds)
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            assets.enumerateObjects { asset, _, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }
                result[asset.localIdentifier, default: []]
                    .append(collection.localizedTitle ?? "Untitled")
            }
            if Task.isCancelled { return result }
            if index % 20 == 0 { await Task.yield() }
        }
        return result
    }
}
