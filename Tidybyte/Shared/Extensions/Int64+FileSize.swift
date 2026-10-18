import Foundation

extension Int64 {
    /// A decimal file size in the user's locale.
    ///
    /// Delegates to `Formatters.fileSize`, which replaced a bare
    /// `ByteCountFormatter` call: that type has no `locale` property at all, so
    /// every user saw "1.5 MB" regardless of whether their convention is
    /// "1,5 MB" (German, Portuguese, Russian) or "١٫٥ م.ب" (Arabic).
    ///
    /// Kept as a property so the ~30 existing call sites keep working; the
    /// locale and the chosen language are resolved inside.
    var formattedFileSize: String {
        Formatters.fileSize(self)
    }
}

extension Sequence {
    /// Total size for elements whose id is in `selectedIds`. Takes explicit
    /// projections so value types with different shapes (`AssetSummary`,
    /// `AnalyzedPhoto`, `CategorizedPhoto`, `PhotoItem`, ...) share one
    /// implementation.
    func totalFileSize(
        selectedIds: Set<String>,
        idOf: (Element) -> String,
        sizeOf: (Element) -> Int64
    ) -> Int64 {
        var total: Int64 = 0
        for element in self where selectedIds.contains(idOf(element)) {
            total += sizeOf(element)
        }
        return total
    }
}

extension Sequence where Element == AssetSummary {
    /// Total `fileSize` for asset ids in `selectedIds`.
    func totalFileSize(selectedIds: Set<String>) -> Int64 {
        totalFileSize(selectedIds: selectedIds, idOf: \.id, sizeOf: \.fileSize)
    }
}
