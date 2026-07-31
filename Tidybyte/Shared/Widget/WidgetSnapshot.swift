import Foundation

/// Small, Codable summary the main app writes to the shared App Group so the
/// widget extension can render without touching PhotoKit. Richer than
/// `StorageSnapshot` (which lacks counts and device capacity), so it's a
/// separate value type. Compiled into BOTH the app and widget targets.
struct WidgetSnapshot: Codable, Sendable {
    var capturedAt: Date
    var usedBytes: Int64
    var totalBytes: Int64
    var screenshotCount: Int
    var screenshotBytes: Int64
    var largeFileCount: Int
    var largeFileBytes: Int64
    var reclaimableBytes: Int64
}
