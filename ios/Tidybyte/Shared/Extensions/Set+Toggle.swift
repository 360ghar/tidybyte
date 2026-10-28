import Foundation

extension Set {
    /// Inserts `element` if absent, removes it if present. Replaces the
    /// `if contains { remove } else { insert }` pattern duplicated across the
    /// cleanup view models.
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}
