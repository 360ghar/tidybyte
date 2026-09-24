import UIKit

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    /// Bumped by every eviction (`removeAllVariants`, `removeAll`) so
    /// in-flight thumbnail loads can drop stale pre-edit bytes instead of
    /// reinserting them (E5). Read via `currentGeneration()`.
    private var generation = 0

    init(countLimit: Int = 200, totalCostLimit: Int = 50 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    /// Cache key for a thumbnail. List thumbnails (200 px or less) and large
    /// views (the Compare screen asks for 600 px) use different keys, so a
    /// cached list thumbnail is never upscaled into a large view.
    nonisolated static func key(for assetId: String, size: CGSize) -> String {
        max(size.width, size.height) <= 200 ? assetId : "\(assetId)#large"
    }

    /// Drops every size and quality variant of one asset.
    func removeAllVariants(of assetId: String) {
        for key in [assetId, "\(assetId)#large"] {
            cache.removeObject(forKey: key as NSString)
            cache.removeObject(forKey: "\(key)#degraded" as NSString)
        }
        generation += 1
    }

    /// Current eviction generation for E5 staleness checks.
    func currentGeneration() -> Int {
        generation
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        // Cost ≈ in-memory bytes so `totalCostLimit` binds real memory
        // (200 full 200px thumbnails otherwise pin ~30–60MB with no ceiling).
        // Per-asset worst case is bounded, not 13MB: the large variant is at
        // most ~600×600×4 ≈ 1.4MB, the list variant ~200×200×4 ≈ 160KB, and
        // each has one degraded twin — ≈ 3.1MB per asset worst case, with
        // `totalCostLimit` (50MB) as the global ceiling.
        let scale = image.scale
        let cost = Int(image.size.width * scale * image.size.height * scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
        // A freshly stored large variant supersedes the upscaled list one, so
        // evict the sibling size class to hold the per-asset bound above.
        if key.hasSuffix("#large") {
            let base = String(key.dropLast("#large".count))
            cache.removeObject(forKey: base as NSString)
            cache.removeObject(forKey: "\(base)#degraded" as NSString)
        }
    }

    /// Drops one entry (E4: used to evict a superseded degraded placeholder).
    func removeImage(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// Drops every cached image. Fallback when incremental change details are
    /// unavailable (SHARED-08), and the memory-warning path — per-change
    /// coherence is selective eviction via `removeImage(for:)`, owned by
    /// `PhotoLibraryService.handleLibraryChange`.
    func removeAll() {
        cache.removeAllObjects()
        generation += 1
    }
}
