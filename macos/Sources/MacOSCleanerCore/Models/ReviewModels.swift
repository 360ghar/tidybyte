import Foundation

public enum DistributionChannel {
    public static var supportsAdvanced: Bool {
        #if APP_STORE
            false
        #else
            true
        #endif
    }
}

public enum ReviewMode: String, Codable, CaseIterable, Sendable {
    case folder, fullMac
}

public struct ReviewScope: Codable, Equatable, Sendable {
    public var mode: ReviewMode = .folder
    public var roots: [URL] = []
    public var includesPhotos = false
    public var exportedChatFolder: URL?
    public init() {}
    public var id: String {
        ([mode.rawValue, includesPhotos ? "photos" : "files"] + roots.map(\.standardizedFileURL.path).sorted())
            .joined(separator: "|")
    }
    public static let presetFolders = ["Pictures", "Movies", "Music", "Downloads", "Documents", "Desktop"]
}

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case image, video, pdf, audio, document, archive, other
    public var title: String {
        switch self {
        case .image: String(localized: "Images")
        case .video: String(localized: "Videos")
        case .pdf: String(localized: "PDFs")
        case .audio: String(localized: "Audio")
        case .document: String(localized: "Documents")
        case .archive: String(localized: "Archives")
        case .other: String(localized: "Other")
        }
    }
}

public struct PhotoResource: Codable, Hashable, Sendable {
    public var name: String
    public var type: Int
    public var uniformType: String
    public var bytes: Int64
    public var hash: String?
    public init(name: String, type: Int, uniformType: String, bytes: Int64 = 0, hash: String? = nil) {
        self.name = name
        self.type = type
        self.uniformType = uniformType
        self.bytes = bytes
        self.hash = hash
    }
}

public enum ReviewSource: Codable, Hashable, Sendable {
    case file(URL)
    case photos(String)
}

public struct MediaFacts: Codable, Hashable, Sendable {
    public var width: Int?
    public var height: Int?
    public var duration: Double?
    public var pageCount: Int?
    public var sharpness: Double?
    public var luminance: Double?
    public var clippedHighlights: Double?
    public var category: SmartCategory = .other
    public var isScreenshot = false
    public var isScreenRecording = false
    public var burstIdentifier: String?
    public var contentIdentifier: String?
    public var capturedAt: Date?
    public var isExportedChatMedia: Bool?
    public init() {}
}

public enum SmartCategory: String, Codable, CaseIterable, Sendable {
    case memes, documents, food, pets, nature, selfies, savedFromApps, other
    public var title: String {
        switch self {
        case .memes: String(localized: "Memes")
        case .documents: String(localized: "Documents")
        case .food: String(localized: "Food")
        case .pets: String(localized: "Pets")
        case .nature: String(localized: "Nature")
        case .selfies: String(localized: "Selfies")
        case .savedFromApps: String(localized: "Saved from Apps")
        case .other: String(localized: "Other")
        }
    }
}

public struct ReviewItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var source: ReviewSource
    public var name: String
    public var kind: MediaKind
    public var bytes: Int64
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var identity: FileIdentity?
    public var root: URL?
    public var linkTarget: URL?
    public var isLink = false
    public var isPackage = false
    public var packageVersion: String?
    public var isDownloaded = true
    public var isCloudSynced = false
    public var resources: [PhotoResource] = []
    public var facts = MediaFacts()
    public var analysisError: String?
    public init(id: String, source: ReviewSource, name: String, kind: MediaKind, bytes: Int64) {
        self.id = id
        self.source = source
        self.name = name
        self.kind = kind
        self.bytes = bytes
    }
    public var url: URL? { if case .file(let url) = source { url } else { nil } }
    public var photoID: String? { if case .photos(let id) = source { id } else { nil } }
    public var version: String { "\(bytes)|\(modifiedAt?.timeIntervalSince1970 ?? 0)|\(packageVersion ?? "")" }
    public var reviewKey: String { "\(id)|\(version)" }
    public var sourceName: String {
        url?.deletingLastPathComponent().path ?? String(localized: "Photos Library")
    }
    public var canChange: Bool { isDownloaded && !isCloudSynced }
    public var canAnalyze: Bool { isDownloaded && !isLink && !isPackage }
}

public enum ReviewFilter: String, Codable, CaseIterable, Sendable {
    case unreviewed, everything, beforeDate, subfolder, largest
    public var title: String {
        switch self {
        case .unreviewed: String(localized: "Not Reviewed Yet")
        case .everything: String(localized: "Everything Here")
        case .beforeDate: String(localized: "Before a Date")
        case .subfolder: String(localized: "One Subfolder")
        case .largest: String(localized: "Largest First")
        }
    }
}

public enum ReviewChoice: String, Codable, Sendable {
    case keep, trash, move, skip
    public var title: String {
        switch self {
        case .keep: String(localized: "Keep")
        case .trash: String(localized: "Remove to Trash or Recently Deleted")
        case .move: String(localized: "Move")
        case .skip: String(localized: "Skip")
        }
    }
}
public struct ReviewDecision: Codable, Sendable {
    public var item: ReviewItem
    public var choice: ReviewChoice
    public var destination: URL?
    public init(item: ReviewItem, choice: ReviewChoice, destination: URL? = nil) {
        self.item = item
        self.choice = choice
        self.destination = destination
    }
}

public struct ReviewSession: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var scopeID: String
    public var items: [ReviewItem]
    public var decisions: [ReviewDecision] = []
    public var protectedGroups: [AnalysisGroup]?
    public var applicationStartedAt: Date?
    public var tool: CleanupTool
    public init(scopeID: String, items: [ReviewItem], tool: CleanupTool = .swipe) {
        self.scopeID = scopeID
        self.items = items
        self.tool = tool
    }
    public var current: ReviewItem? {
        let decided = Set(decisions.map(\.item.id))
        return items.first { !decided.contains($0.id) }
    }
    public var pendingChanges: [ReviewDecision] { decisions.filter { $0.choice == .trash || $0.choice == .move } }
}

public enum CleanupTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case duplicates, similar, blurry, large, bursts, screenRecordings
    case screenshots, categories, downloads
    case videoCompression, imageCompression, formatPairs, swipe
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .duplicates: String(localized: "Duplicates")
        case .similar: String(localized: "Similar Files")
        case .blurry: String(localized: "Blurry Images")
        case .large: String(localized: "Large Files")
        case .bursts: String(localized: "Burst Sequences")
        case .screenRecordings: String(localized: "Screen Recordings")
        case .screenshots: String(localized: "Screenshots")
        case .categories: String(localized: "Smart Categories")
        case .downloads: String(localized: "Downloads & Chat Media")
        case .videoCompression: String(localized: "Video Compression")
        case .imageCompression: String(localized: "Image Compression")
        case .formatPairs: String(localized: "Duplicate-Format Pairs")
        case .swipe: String(localized: "Swipe Review")
        }
    }
    public var group: Int {
        switch self {
        case .duplicates, .similar, .blurry, .large, .bursts, .screenRecordings: 0
        case .screenshots, .categories, .downloads, .swipe: 1
        case .videoCompression, .imageCompression, .formatPairs: 2
        }
    }
    public var isCompression: Bool { self == .videoCompression || self == .imageCompression }
}

public struct AnalysisGroup: Codable, Identifiable, Sendable {
    public var id: String
    public var tool: CleanupTool
    public var memberIDs: [String]
    public var bestID: String
    public var explanation: String
    public init(
        tool: CleanupTool, memberIDs: [String], bestID: String, explanation: String, isVisualMatch: Bool = false
    ) {
        self.id = tool.rawValue + (isVisualMatch ? ":visual:" : ":exact:") + memberIDs.sorted().joined(separator: "|")
        self.tool = tool
        self.memberIDs = memberIDs
        self.bestID = bestID
        self.explanation = explanation
    }
}

public struct AnalysisResult: Codable, Sendable {
    public var generation: UUID
    public var scopeID: String
    public var settings: CleanupSettings
    public var items: [ReviewItem]
    public var groups: [AnalysisGroup]
    public var completedAt = Date()
    public var isFresh = true
    public var settingsVersion: String { settings.analysisVersion }
}

public enum ImageQuality: String, CaseIterable, Codable, Sendable {
    case high, balanced, small
    public var quality: Double {
        switch self {
        case .high: 0.9
        case .balanced: 0.8
        case .small: 0.65
        }
    }
}

public struct CleanupSettings: Codable, Equatable, Sendable {
    public var analysisVersion: String {
        "\(similarSeconds)|\(blurSensitivity)|\(categorySensitivity)|\(largeMegabytes)"
    }
    public var similarSeconds: Double = 5
    public var blurSensitivity = 1
    public var categorySensitivity = 1
    public var largeMegabytes: Double = 10
    public var defaultFilter: ReviewFilter = .unreviewed
    public var videoHeight = 1080
    public var imageQuality: ImageQuality = .balanced
    public var reminderEnabled = false
    public var reminderWeekday = 2
    public init() {}
}

public enum OperationState: String, Codable, Sendable {
    case prepared, outputReady, complete, failed, interrupted
    public var title: String {
        switch self {
        case .prepared: String(localized: "Prepared")
        case .outputReady: String(localized: "Output ready; original retained")
        case .complete: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .interrupted: String(localized: "Interrupted; check outputs")
        }
    }
}
public struct ActivityEvent: Codable, Identifiable, Sendable {
    public var id: String
    public var date = Date()
    public var tool: CleanupTool
    public var item: ReviewItem
    public var action: String
    public var bytes: Int64
    public var outputBytes: Int64 = 0
    public var outputURL: URL?
    public var replacementURL: URL?
    public var outputIdentity: FileIdentity?
    public var recoveryBookmark: Data?
    public var replacementPhotoID: String?
    public var state: OperationState = .prepared
    public var error: String?
    public var restored = false
    public var restoredAt: Date?
    public var restoreStartedAt: Date?
    public init(id: String = UUID().uuidString, tool: CleanupTool, item: ReviewItem, action: String) {
        self.id = id
        self.tool = tool
        self.item = item
        self.action = action
        self.bytes = item.bytes
    }
    public var savings: Int64 {
        restored ? 0 : completedReduction
    }
    public var completedReduction: Int64 {
        guard state == .complete, action != "move" else { return 0 }
        return max(0, bytes - outputBytes)
    }
}

public struct CompressionJob: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var item: ReviewItem
    public var progress: Double = 0
    public var estimatedBytes: Int64
    public var event: ActivityEvent?
    public init(item: ReviewItem, estimatedBytes: Int64) {
        self.item = item
        self.estimatedBytes = estimatedBytes
    }
}

public struct CleanupSnapshot: Codable, Identifiable, Sendable {
    public var id: String
    public var scopeID: String
    public var date: Date
    public var bytes: Int64
    public var count: Int
    public init(id: String, scopeID: String, date: Date, bytes: Int64, count: Int) {
        self.id = id
        self.scopeID = scopeID
        self.date = date
        self.bytes = bytes
        self.count = count
    }
}

public struct CleanupProgress: Sendable {
    public var phase: String
    public var completed: Int
    public var total: Int
    public init(_ phase: String, completed: Int, total: Int) {
        self.phase = phase
        self.completed = completed
        self.total = total
    }
}

public enum CleanupError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}
