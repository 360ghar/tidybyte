import Foundation

/// Presentation helper for byte counts. Kept in the Core module because
/// findings, plans, and services all format sizes; lives in its own file so
/// the safety-policy source stays focused on path safety.
public extension Int64 {
    var formattedByteCount: String {
        // ByteCountFormatter renders 0 as "Zero KB", which is inconsistent with
        // the "31 bytes" style it uses for other small values. Render zero
        // explicitly so all sizes share the same format.
        if self == 0 {
            return String(localized: "0 bytes", comment: "Byte count for an empty file")
        }
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
