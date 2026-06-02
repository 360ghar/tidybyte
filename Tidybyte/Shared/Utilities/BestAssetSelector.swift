import Foundation

/// Shared, deterministic "which asset to keep" ranking used by the cleanup tools.
///
/// This is the **metadata-only** ladder (no Vision/quality signals): highest
/// resolution, then favorited, then most recent, then a stable `id` tiebreak so
/// the result never depends on input ordering. `DuplicateFinder` uses it
/// directly — near-identical assets share visual quality, so metadata is enough.
/// The Similar Photos tool layers a quality-weighted score (sharpness/exposure)
/// on top and falls back to this comparator only to break near-ties.
enum BestAssetSelector {
    /// Strict ordering predicate for `max(by:)`: returns `true` when `a` is a
    /// *worse* keeper than `b`, so `max(by:)` yields the best. Deterministic —
    /// the final `id` comparison guarantees a stable winner for otherwise-equal
    /// assets regardless of input order.
    static func isWorse(_ a: AssetSummary, than b: AssetSummary) -> Bool {
        let aPixels = a.pixelWidth * a.pixelHeight
        let bPixels = b.pixelWidth * b.pixelHeight
        if aPixels != bPixels { return aPixels < bPixels }
        if a.isFavorite != b.isFavorite { return !a.isFavorite }
        let aDate = a.creationDate ?? .distantPast
        let bDate = b.creationDate ?? .distantPast
        if aDate != bDate { return aDate < bDate }
        return a.id > b.id   // smaller id wins, for stability
    }

    /// The best keeper by metadata alone, or `nil` only for an empty input.
    static func bestByMetadata(from assets: [AssetSummary]) -> AssetSummary? {
        assets.max(by: isWorse)
    }
}
