import Foundation
import SwiftData

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

    init(
        assetLocalIdentifier: String,
        replacementAssetLocalIdentifier: String? = nil,
        originalSizeBytes: Int64,
        compressedSizeBytes: Int64,
        compressedAt: Date = .now,
        exportPreset: String,
        outcome: String = "completed",
        mediaType: String = "video"
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.replacementAssetLocalIdentifier = replacementAssetLocalIdentifier
        self.originalSizeBytes = originalSizeBytes
        self.compressedSizeBytes = compressedSizeBytes
        self.compressedAt = compressedAt
        self.exportPreset = exportPreset
        self.outcome = outcome
        self.mediaType = mediaType
    }

    /// True when the record represents a successful compression (the
    /// replacement was saved and the original deleted). Failed records carry
    /// `compressedSizeBytes == 0`; they must be excluded from savings totals
    /// and shown as failures, not as huge green savings (COMP-01).
    var succeeded: Bool { outcome == "completed" }

    /// Space reclaimed by this record. Failed records contribute zero.
    var savedBytes: Int64 {
        succeeded ? max(0, originalSizeBytes - compressedSizeBytes) : 0
    }
}
