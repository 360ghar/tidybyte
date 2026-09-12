import UIKit

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    init(countLimit: Int = 200, totalCostLimit: Int = 50 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        // Cost ≈ in-memory bytes so `totalCostLimit` binds real memory
        // (200 full 200px thumbnails otherwise pin ~30–60MB with no ceiling).
        let scale = image.scale
        let cost = Int(image.size.width * scale * image.size.height * scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
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
    }
}
