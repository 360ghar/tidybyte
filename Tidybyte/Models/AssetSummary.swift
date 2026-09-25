import Foundation

enum MediaType: String, Sendable {
    case photo
    case video
    case audio
    case unknown
}

/// Where an asset most likely originated. Derived heuristically from PhotoKit
/// metadata (subtypes, location, original filename) — see
/// `PhotoLibraryService.detectOrigin`. Used by the Smart Categories tool to
/// surface media that wasn't captured with the camera (e.g. images saved from
/// messaging or social apps).
enum AssetOrigin: String, Sendable {
    case camera
    case savedFromApp
    case screenshot
    case unknown
}

/// Burst keeper hint from PhotoKit's `burstSelectionTypes`. Later cases are
/// a stronger reason to keep the frame.
enum BurstPick: Sendable, Hashable, Comparable {
    case none
    case iPhone
    case user
}

struct AssetSummary: Identifiable, Sendable, Hashable {
    let id: String
    let mediaType: MediaType
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let fileSize: Int64
    let filename: String?
    let isFavorite: Bool
    let isBurst: Bool
    let burstIdentifier: String?
    let isLivePhoto: Bool
    let isScreenshot: Bool
    let isLocallyAvailable: Bool
    var assetOrigin: AssetOrigin = .unknown
    /// The frame the user or the camera picked inside a burst. `.none` for
    /// every asset that is not a burst frame.
    var burstPick: BurstPick = .none
    var isScreenRecording = false
    var isCinematic = false
    var isSpatial = false

    /// The original file is HEIC/HEIF (already an efficient format).
    var isHEIC: Bool {
        guard let filename else { return false }
        return [".heic", ".heif"].contains {
            filename.range(of: $0, options: [.caseInsensitive, .backwards, .anchored]) != nil
        }
    }

    var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var formattedDuration: String {
        guard duration > 0 else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Human-readable size for labels/confirmations, tolerant of unavailable
    /// metadata: a 0 fileSize (iCloud-only or KVC-unreadable) renders as
    /// "Size unavailable" instead of a misleading "Zero KB" (SHARED-03/E1 —
    /// the old `formattedFileSize` duplicate that rendered "Zero KB" is gone;
    /// byte-level totals keep using `Int64.formattedFileSize`).
    var displaySize: String {
        fileSize == 0 ? "Size unavailable" : fileSize.formattedFileSize
    }
}
