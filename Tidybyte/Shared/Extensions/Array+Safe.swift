import Foundation

extension Array {
    /// Bounds-checked subscript: returns `nil` instead of trapping when `index`
    /// is out of range. Used by the paged comparison views while the current
    /// page index trails the (shrunken) asset list during deletion.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
