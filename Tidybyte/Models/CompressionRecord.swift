import Foundation
import SwiftData

/// Typed media kinds for compression history. Stored as `String` raw values
/// on `CompressionRecord` (SwiftData lightweight migration safe).
enum CompressionMediaType: String, Sendable {
    case video
    case photo
    case livePhoto
    case still
}

/// Typed outcomes for compression history. Stored as `String` raw values.
enum CompressionOutcome: String, Sendable {
    case pending
    case completed
    case skipped
    case failed
}

@Model
final class CompressionRecord {
    var assetLocalIdentifier: String
    var replacementAssetLocalIdentifier: String?
    var originalSizeBytes: Int64
    var compressedSizeBytes: Int64
    var compressedAt: Date
    var exportPreset: String
    var outcome: String
    /// "video" or "photo". Defaulted so existing records migrate automatically
    /// (SwiftData lightweight migration) and old call sites keep compiling.
    var mediaType: String = "video"
    /// True once the service has begun the library save that creates the
    /// replacement. Reconcile uses it to tell two very different states apart:
    /// false means the attempt died before anything was written to the library
    /// (nothing durable happened → the row can be dropped), true means a copy
    /// may exist whose id never reached the journal (dropping the row would
    /// hide that duplicate). Defaulted like `mediaType`, for the same
    /// lightweight-migration reason.
    var saveAttempted: Bool = false

    init(
        assetLocalIdentifier: String,
        replacementAssetLocalIdentifier: String? = nil,
        originalSizeBytes: Int64,
        compressedSizeBytes: Int64,
        compressedAt: Date = .now,
        exportPreset: String,
        outcome: String = "completed",
        mediaType: String = "video",
        saveAttempted: Bool = false
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.replacementAssetLocalIdentifier = replacementAssetLocalIdentifier
        self.originalSizeBytes = originalSizeBytes
        self.compressedSizeBytes = compressedSizeBytes
        self.compressedAt = compressedAt
        self.exportPreset = exportPreset
        self.outcome = outcome
        self.mediaType = mediaType
        self.saveAttempted = saveAttempted
    }

    /// True when the record represents a successful compression (the
    /// replacement was saved and the original deleted). Failed records must
    /// be excluded from savings totals and shown as failures, not as huge
    /// green savings (COMP-01) — `savedBytes` returns zero unless completed.
    var succeeded: Bool { outcome == CompressionOutcome.completed.rawValue }

    /// True when the record represents a failed compression. Distinct from
    /// `succeeded` (which is false for both failures AND intentional skips):
    /// skipped records are not failures and must not render a red badge.
    var isFailed: Bool { outcome == CompressionOutcome.failed.rawValue }

    /// True while the save→delete swap is still in flight or was interrupted
    /// by a crash (D1). Reconciliation resolves these on tool load; they must
    /// never render as savings.
    var isPending: Bool { outcome == CompressionOutcome.pending.rawValue }

    /// Space reclaimed by this record. Failed records contribute zero.
    var savedBytes: Int64 {
        succeeded ? max(0, originalSizeBytes - compressedSizeBytes) : 0
    }
}
