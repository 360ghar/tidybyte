import Foundation

/// Binary search helpers for sorted path arrays.
enum SortedPathSearch {
    /// Returns the index of the first element whose path is >= `prefix`.
    static func lowerBound(_ paths: [String], _ prefix: String) -> Int {
        var lo = 0
        var hi = paths.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if paths[mid] < prefix { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Returns the index of the first element whose path is >= the character after `prefix`.
    /// Uses Unicode scalar comparison for correct handling of non-ASCII path characters.
    static func upperBound(_ paths: [String], _ prefix: String) -> Int {
        // Build the upper bound by incrementing the last Unicode scalar of the prefix.
        // This ensures correct ordering for all Unicode characters, not just ASCII.
        let upperPrefix: String
        if let lastScalar = prefix.unicodeScalars.last,
           let incremented = Unicode.Scalar(lastScalar.value + 1) {
            let base = prefix.unicodeScalars.dropLast()
            upperPrefix = String(base) + String(incremented)
        } else {
            upperPrefix = prefix
        }
        var lo = 0
        var hi = paths.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if paths[mid] < upperPrefix { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
