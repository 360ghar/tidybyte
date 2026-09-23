import Foundation

/// Pure, `Sendable` rollup of a photo library shared by the app's daily scan
/// (`StorageSnapshot`), the storage dashboard, and the widget snapshot — ONE
/// builder so the three surfaces can't drift apart (APP-04).
struct MediaLibraryStats: Sendable {
    var photoBytes: Int64 = 0
    var videoBytes: Int64 = 0
    var screenshotBytes: Int64 = 0
    var livePhotoBytes: Int64 = 0
    var otherBytes: Int64 = 0
    var totalBytes: Int64 = 0

    var photoCount: Int = 0
    var videoCount: Int = 0
    var screenshotCount: Int = 0
    var livePhotoCount: Int = 0
    var otherCount: Int = 0

    /// Files at/above the user's large-file threshold, EXCLUDING screenshots —
    /// `toCleanCount` adds this to `screenshotCount`, so a
    /// screenshot that also clears the threshold is never double-counted
    /// (APP-12).
    var largeFileCount: Int = 0
    var largeFileBytes: Int64 = 0

    /// Videos strictly over 100 MB — the honest "video compression"
    /// candidate set, matching what VideoCompression actually offers
    /// (E9; replaces three write-only rollup fields).
    var largeVideoCount: Int = 0

    /// Widget "N to clean" figure: every screenshot plus every large file that
    /// isn't already a screenshot (APP-12).
    var toCleanCount: Int { screenshotCount + largeFileCount }

    /// Total estimated reclaimable, computed with the SAME disjoint priority
    /// bucketing as the dashboard's reclaim wins (screenshots → live photos →
    /// large videos → saved-from-apps → remaining large files), so the widget
    /// and the dashboard hero always agree (APP-04).
    var reclaimableBytes: Int64 = 0

    static func build(from assets: [AssetSummary], largeFileThresholdBytes: Int64) -> MediaLibraryStats {
        var stats = MediaLibraryStats()

        for asset in assets {
            let size = asset.fileSize
            stats.totalBytes += size
            switch asset.mediaType {
            case .photo:
                if asset.isScreenshot {
                    stats.screenshotBytes += size
                    stats.screenshotCount += 1
                } else if asset.isLivePhoto {
                    stats.livePhotoBytes += size
                    stats.livePhotoCount += 1
                } else {
                    stats.photoBytes += size
                    stats.photoCount += 1
                }
            case .video:
                stats.videoBytes += size
                stats.videoCount += 1
                if size > ReclaimBucketer.largeVideoByteThreshold {
                    stats.largeVideoCount += 1
                }
            default:
                stats.otherBytes += size
                stats.otherCount += 1
            }
        }

        // Large files exclude screenshots (counted separately above).
        for asset in assets where asset.fileSize >= largeFileThresholdBytes && !asset.isScreenshot {
            stats.largeFileCount += 1
            stats.largeFileBytes += asset.fileSize
        }

        // Reclaimable mirrors the dashboard's disjoint win bucketing exactly.
        stats.reclaimableBytes = ReclaimBucketer
            .buckets(from: assets, largeFileThresholdBytes: largeFileThresholdBytes)
            .reduce(Int64(0)) { $0 + $1.bytes }

        return stats
    }
}

/// Disjoint priority bucketing shared by the Storage dashboard's reclaim wins
/// and `MediaLibraryStats`, so their totals can never drift apart (APP-04).
/// Each asset contributes to at most one bucket, in priority order:
/// screenshots → live photos → large videos (>100 MB) → saved-from-apps →
/// remaining large files.
enum ReclaimBucketer {
    /// Videos strictly above this are compression candidates (100 decimal MB).
    static let largeVideoByteThreshold: Int64 = 100 * 1_000_000

    struct Bucket: Identifiable, Sendable {
        let key: String
        let count: Int
        let bytes: Int64
        let ids: [String]
        var id: String { key }
    }

    static func buckets(from assets: [AssetSummary], largeFileThresholdBytes: Int64) -> [Bucket] {
        // Only items stored on this iPhone: deleting an iCloud-only item frees
        // iCloud space, not device space, and every hero that shows this total
        // sits next to device storage.
        let assets = assets.filter(\.isLocallyAvailable)
        var map: [String: (count: Int, bytes: Int64, ids: [String])] = [:]
        var claimed = Set<String>()

        /// Pick unclaimed assets matching `predicate`, record them under `key`, and
        /// mark them claimed. `estimate` maps total bytes → reclaimable (e.g. Live
        /// Photos / videos halved for compression).
        func claim(_ key: String, matching predicate: (AssetSummary) -> Bool, estimate: (Int64) -> Int64 = { $0 }) {
            var picks: [AssetSummary] = []
            for asset in assets where predicate(asset) && !claimed.contains(asset.id) {
                picks.append(asset)
            }
            guard !picks.isEmpty else { return }
            map[key] = (
                count: picks.count,
                bytes: estimate(picks.reduce(Int64(0)) { $0 + $1.fileSize }),
                ids: picks.map(\.id)
            )
            claimed.formUnion(picks.map(\.id))
        }

        // 1. Screenshots (highest priority — full reclaimable)
        claim("screenshots", matching: { $0.isScreenshot })

        // 2. Live Photos (~50% reclaimable via conversion to still)
        claim("livePhotos", matching: { $0.isLivePhoto }, estimate: { $0 / 2 })

        // 3. Large Videos (~50% reclaimable via compression)
        claim("largeVideos", matching: { $0.mediaType == .video && $0.fileSize > Self.largeVideoByteThreshold }, estimate: { $0 / 2 })

        // 4. Saved from Apps (exact origin — full reclaimable via swipe review)
        claim("savedFromApps", matching: { $0.assetOrigin == .savedFromApp })

        // 5. Large Files (user-configurable threshold) — full reclaimable. NOTE:
        // because bucketing is disjoint by priority, this count can be *smaller*
        // than what `.cleanup(.largeFiles)` lists — a screenshot / large video /
        // saved-from-app already claimed above is excluded here even though it
        // clears the threshold. The hero total stays coherent (each asset counted
        // once) at the cost of this per-tool undercount; that's the intended
        // tradeoff.
        claim("largeFiles", matching: { $0.fileSize >= largeFileThresholdBytes })

        return map.map { key, value in
            Bucket(key: key, count: value.count, bytes: value.bytes, ids: value.ids)
        }
    }
}
