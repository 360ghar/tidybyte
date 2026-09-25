import Foundation
import SwiftData

/// One logged cleanup outcome for the Activity & Savings ledger. Written only
/// when a delete/compression actually succeeded (never on error, cancellation,
/// or a no-op), so the totals it feeds are a floor on real savings rather than
/// an optimistic estimate.
///
/// Compression and Live Photo conversion are NOT written here — those already
/// have `CompressionRecord` with the crash-safe `CompressionJournal`. The
/// summary builder merges both sources instead, so the two write paths stay
/// independent.
enum CleanupActivityKind: String, CaseIterable, Sendable {
    case swipe
    case duplicates
    case similar
    case screenshots
    case screenRecordings
    case chatMedia
    case blurry
    case smartCategories
    case largeFiles
    case bursts
    // Never written by the ledger — these kinds exist so the summary can fold
    // successful `CompressionRecord` rows into the same per-tool breakdown.
    case videoCompression
    case photoCompression
    case livePhotos

    /// The tool a "Review again" button should open. `nil` for swipe (which is
    /// a session, not a cleanup tool).
    var tool: CleanupTool? {
        switch self {
        case .swipe: nil
        case .duplicates: .duplicates
        case .similar: .similar
        case .screenshots: .screenshots
        case .screenRecordings: .screenRecordings
        case .chatMedia: .chatMedia
        case .blurry: .blurry
        case .smartCategories: .smartCategories
        case .largeFiles: .largeFiles
        case .bursts: .bursts
        case .videoCompression: .videoCompression
        case .photoCompression: .photoCompression
        case .livePhotos: .livePhotos
        }
    }

    var title: String {
        switch self {
        case .swipe: "Swipe session"
        default: tool?.name ?? rawValue
        }
    }

    var icon: String {
        switch self {
        case .swipe: "rectangle.portrait.on.rectangle.portrait.angled"
        default: tool?.icon ?? "sparkles"
        }
    }

    /// Compression media types map onto the kinds the breakdown renders.
    static func from(compressionMediaType rawValue: String) -> CleanupActivityKind {
        switch CompressionMediaType(rawValue: rawValue) {
        case .photo: .photoCompression
        case .livePhoto, .still: .livePhotos
        case .video, .none: .videoCompression
        }
    }
}

@Model
final class CleanupActivityRecord {
    /// `CleanupActivityKind` raw value.
    var kind: String
    var itemCount: Int
    /// Sum of the sizes that were KNOWN at delete time. iCloud-only assets
    /// report a 0 file size, so this under-reports for such libraries — the UI
    /// says so rather than guessing a size.
    var freedBytes: Int64
    var recordedAt: Date

    init(kind: String, itemCount: Int, freedBytes: Int64, recordedAt: Date = .now) {
        self.kind = kind
        self.itemCount = itemCount
        self.freedBytes = freedBytes
        self.recordedAt = recordedAt
    }
}
