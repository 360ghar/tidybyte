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

    var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var formattedDuration: String {
        guard duration > 0 else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
