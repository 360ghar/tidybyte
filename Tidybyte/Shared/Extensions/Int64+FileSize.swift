import Foundation

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
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
