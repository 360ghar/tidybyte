import Foundation

public enum ScanMode: String, CaseIterable, Codable, Identifiable, Sendable {
    // Original crawl-based modes
    case selectedFolders
    case homeFolder
    case developerCleanup
    // mo clean known-path sections
    case deepSystem
    case userEssentials
    case finderMetadata
    case macOSSystemCaches
    case sandboxedAppCaches
    case browsers
    case cloudStorage
    case officeApps
    case developerTools
    case devApplications
    case vmTools
    case applicationSupport
    case uninstalledAppData
    case appleSiliconUpdates
    case iosBackups
    case timeMachineBackups
    case largeFiles

    public var id: String { rawValue }

    /// True for the mo clean known-path sections that delegate to `MoCleanScanner`.
    public var isSystemCleanSection: Bool {
        switch self {
        case .selectedFolders, .homeFolder, .developerCleanup:
            return false
        case .deepSystem, .userEssentials, .finderMetadata, .macOSSystemCaches,
             .sandboxedAppCaches, .browsers, .cloudStorage, .officeApps,
             .developerTools, .devApplications, .vmTools, .applicationSupport,
             .uninstalledAppData, .appleSiliconUpdates, .iosBackups,
             .timeMachineBackups, .largeFiles:
            return true
        }
    }

    /// Maps a system-clean section to its `SystemCleanSection` registry case.
    public var systemCleanSection: MoCleanScanner.SystemCleanSection? {
        guard isSystemCleanSection else { return nil }
        return MoCleanScanner.SystemCleanSection(rawValue: rawValue)
    }
}

public enum PrivacyMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case localOnly
    case metadataOnlyAI
    case snippetsAI
    case visionAI
    case fullDocumentAI

    public var id: String { rawValue }
}

public enum CleanupPosture: String, CaseIterable, Codable, Identifiable, Sendable {
    case conservative
    case balanced
    case aggressive

    public var id: String { rawValue }
}

public enum FileSource: String, Codable, Sendable {
    case local
    case iCloudLocal
    case googleDriveLocal
    case dropboxLocal
    case oneDriveLocal
    case external
}

public enum FileKind: String, Codable, Sendable {
    case regularFile
    case directory
    case package
    case symlink
    case other
}

public enum FindingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    // Original categories
    case largeFile
    case duplicate
    case cache
    case log
    case oldDownload
    case oldInstaller
    case screenshot
    case developerArtifact
    case appLeftover
    case codingAgentArtifact
    case organization
    case packageManagerCleanup
    case dockerCleanup
    case protected
    // mo clean section categories
    case systemDeep
    case userEssentials
    case finderMetadata
    case macOSSystemCache
    case sandboxedAppCache
    case browserCache
    case cloudStorageCache
    case officeAppCache
    case developerToolCache
    case developmentAppCache
    case vmToolCache
    case applicationSupportCache
    case uninstalledAppData
    case appleSiliconUpdate
    case iosDeviceBackup
    case timeMachineBackup
    case largeFileReview

    public var id: String { rawValue }

    /// Localized, human-readable name for the category. Used in reports and
    /// any other user-facing surface; never display `rawValue` (snake_case).
    public var displayName: String {
        switch self {
        case .largeFile: String(localized: "Large File", comment: "Finding category: large file")
        case .duplicate: String(localized: "Duplicate", comment: "Finding category: duplicate")
        case .cache: String(localized: "Cache", comment: "Finding category: cache")
        case .log: String(localized: "Log", comment: "Finding category: log")
        case .oldDownload: String(localized: "Old Download", comment: "Finding category: old download")
        case .oldInstaller: String(localized: "Old Installer", comment: "Finding category: old installer")
        case .screenshot: String(localized: "Screenshot", comment: "Finding category: screenshot")
        case .developerArtifact: String(localized: "Developer Artifact", comment: "Finding category: developer artifact")
        case .appLeftover: String(localized: "App Leftover", comment: "Finding category: app leftover")
        case .codingAgentArtifact: String(localized: "Coding Agent Artifact", comment: "Finding category: coding agent artifact")
        case .organization: String(localized: "Organization", comment: "Finding category: organization")
        case .packageManagerCleanup: String(localized: "Package Manager Cleanup", comment: "Finding category: package manager cleanup")
        case .dockerCleanup: String(localized: "Docker Cleanup", comment: "Finding category: docker cleanup")
        case .protected: String(localized: "Protected", comment: "Finding category: protected")
        case .systemDeep: String(localized: "Deep System", comment: "Finding category: deep system")
        case .userEssentials: String(localized: "User Essentials", comment: "Finding category: user essentials")
        case .finderMetadata: String(localized: "Finder Metadata", comment: "Finding category: finder metadata")
        case .macOSSystemCache: String(localized: "macOS System Cache", comment: "Finding category: macOS system cache")
        case .sandboxedAppCache: String(localized: "Sandboxed App Cache", comment: "Finding category: sandboxed app cache")
        case .browserCache: String(localized: "Browser Cache", comment: "Finding category: browser cache")
        case .cloudStorageCache: String(localized: "Cloud Storage Cache", comment: "Finding category: cloud storage cache")
        case .officeAppCache: String(localized: "Office App Cache", comment: "Finding category: office app cache")
        case .developerToolCache: String(localized: "Developer Tool Cache", comment: "Finding category: developer tool cache")
        case .developmentAppCache: String(localized: "Development App Cache", comment: "Finding category: development app cache")
        case .vmToolCache: String(localized: "VM Tool Cache", comment: "Finding category: VM tool cache")
        case .applicationSupportCache: String(localized: "Application Support Cache", comment: "Finding category: application support cache")
        case .uninstalledAppData: String(localized: "Uninstalled App Data", comment: "Finding category: uninstalled app data")
        case .appleSiliconUpdate: String(localized: "Apple Silicon Update", comment: "Finding category: Apple Silicon update")
        case .iosDeviceBackup: String(localized: "iOS Device Backup", comment: "Finding category: iOS device backup")
        case .timeMachineBackup: String(localized: "Time Machine Backup", comment: "Finding category: Time Machine backup")
        case .largeFileReview: String(localized: "Large File Review", comment: "Finding category: large file review")
        }
    }
}

public enum RiskLevel: String, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case low
    case medium
    case high
    case forbidden

    public var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .forbidden: 3
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum ActionType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Move file to Trash (reversible via undo within 30 days).
    case moveToTrash
    /// Restore a previously trashed or moved file to its original location.
    case restore
    /// Move file to a specified destination directory.
    case move
    /// Rename a file in place. Phase 2 — not yet implemented.
    case rename
    /// Apply a Finder tag to a file for organization.
    case tag
    /// Offload a local copy to cloud storage. Phase 2 — not yet implemented.
    case offloadLocalCopy
    /// Create a bookmark-based alias in the Tidybyte Aliases folder.
    case createAlias
    /// Create a symbolic link in the Tidybyte Links folder.
    case createSymlink
    /// Zip a file and trash the original. Two undo records created.
    case archive
    /// Run a cloud provider cleanup command. Phase 2 — not yet implemented.
    case runProviderCleanup
    /// Run a package manager cleanup command (brew cleanup, docker prune, etc.).
    case runPackageManagerCleanup
    /// Inspection-only action — no file modification. Used for large files needing review.
    case inspectOnly
    /// Fold an exact-duplicate file onto its keeper as an APFS clone: the path,
    /// name, metadata and contents stay exactly as they were, but the duplicate
    /// stops paying for its own storage blocks. Nothing is deleted and undo
    /// re-splits the copy into a real private file.
    case cloneDeduplicate
    /// Undo-inverse of `cloneDeduplicate`: replace a folded clone with a real
    /// private copy of the data at the same path. Never planned or executed
    /// directly — only referenced by `UndoRecord.inverseAction`.
    case unfoldClone

    public var id: String { rawValue }
}

public enum PlanStatus: String, Codable, Sendable {
    case proposed
    case partiallyApproved
    case executing
    case completed
    case cancelled
}

public enum PlannedActionStatus: String, Codable, Sendable {
    case proposed
    case approved
    case rejected
    case executing
    case completed
    case failed
    case skipped
}

public enum UserDecision: String, Codable, Sendable {
    case undecided
    case approved
    case rejected
    case alwaysDoThis
    case neverDoThisHere
}

public enum UndoStatus: String, Codable, Sendable {
    /// Written BEFORE the filesystem mutation happens, so a crash between the
    /// mutation and the follow-up update leaves a recoverable trail.
    case pending
    case available
    case restored
    case expired
    case notUndoable
    case partiallyUndoable
    case reinstallable
    case failed
}

public enum ProjectStatus: String, Codable, Sendable {
    case active
    case inactive
    case orphaned
    case archived
}

public enum RelationshipEdgeType: String, Codable, Sendable {
    case duplicate
    case generatedFrom
    case sameProject
    case exportOf
    case backupOf
    case versionOf
    case manifestOf
    case temporaryArtifactOf
    case nearDuplicateOf
    case cloudCopyOf
}

public enum ProviderCapability: String, Codable, Sendable {
    case canMove
    case canTrash
    case canRestore
    case canTag
}

/// Type-safe flags indicating why a file is protected or has elevated risk.
/// Replaces raw string matching at safety-critical boundaries.
public enum RiskFlag: String, Codable, CaseIterable, Hashable, Sendable {
    case sipProtectedSystemPath = "sip_protected_system_path"
    case protectedDirectory = "protected_directory"
    case protectedFile = "protected_file"
    case secretOrCertificate = "secret_or_certificate"
    case projectManifest = "project_manifest"
    case sourceOrConfig = "source_or_config"
    case cloudSyncedLocalPath = "cloud_synced_local_path"
    case codingAgentMemoryOrConfig = "coding_agent_memory_or_config"
    case insideTrash = "inside_trash"
    /// Visible in review but never executable (e.g. Xcode archives hold the
    /// dSYMs for shipped builds and cannot be rebuilt from source).
    case reviewOnly = "review_only"
}

public struct FileIdentity: Codable, Hashable, Sendable {
    public var deviceIdentifier: UInt64?
    public var inodeIdentifier: UInt64?
    public var resourceIdentifier: String?
    /// Logical size in bytes at scan time. Compared at mutation time so an
    /// in-place rewrite (same inode, new content) fails verification instead
    /// of passing a device/inode-only check.
    public var sizeBytes: Int64?
    /// Content modification time at scan time. Compared loosely (1s tolerance)
    /// at mutation time for the same in-place-rewrite detection.
    public var modifiedAt: Date?

    public init(deviceIdentifier: UInt64?, inodeIdentifier: UInt64?, resourceIdentifier: String?, sizeBytes: Int64? = nil, modifiedAt: Date? = nil) {
        self.deviceIdentifier = deviceIdentifier
        self.inodeIdentifier = inodeIdentifier
        self.resourceIdentifier = resourceIdentifier
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

/// Stable file identifier: persists across scans for the same path+content
/// generation so regret rules and hash caches survive re-scans. Device IDs
/// are excluded (unstable across reboots/remounts); the mtime bucket absorbs
/// sub-second timestamp jitter. Swift's `hashValue` is seeded per process,
/// so FNV-1a is used instead to keep IDs stable across launches.
public enum StableFileID {
    public static func forStandardizedPath(_ path: String, sizeBytes: Int64, modifiedAt: Date?) -> String {
        let bucket = modifiedAt.map { Int64($0.timeIntervalSince1970) } ?? 0
        var hash: UInt64 = 14_695_901_032_517_790_711
        for byte in path.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "file-\(hash)-\(sizeBytes)-\(bucket)"
    }
}

/// Protocol for types that belong to a scan session and can provide its ID.
protocol ScanSessionScoped {
    var scanSessionID: String { get }
}

public enum ScanSessionStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

public struct ScanSession: Codable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Date
    public var completedAt: Date?
    public var scanType: ScanMode
    public var rootURLs: [URL]
    public var permissionsSnapshot: String
    public var status: ScanSessionStatus
    public var totalFilesSeen: Int
    public var totalBytesSeen: Int64
    public var errorsCount: Int

    public init(
        id: String = UUID().uuidString,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        scanType: ScanMode,
        rootURLs: [URL],
        permissionsSnapshot: String,
        status: ScanSessionStatus = .running,
        totalFilesSeen: Int = 0,
        totalBytesSeen: Int64 = 0,
        errorsCount: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.scanType = scanType
        self.rootURLs = rootURLs
        self.permissionsSnapshot = permissionsSnapshot
        self.status = status
        self.totalFilesSeen = totalFilesSeen
        self.totalBytesSeen = totalBytesSeen
        self.errorsCount = errorsCount
    }
}

public struct Volume: Codable, Identifiable, Sendable {
    public var id: String
    public var mountURL: URL
    public var volumeName: String
    public var volumeUUID: String?
    public var isInternal: Bool
    public var isExternal: Bool
    public var isNetwork: Bool
    public var isCloudSynced: Bool
    public var capacityBytes: Int64?
    public var availableBytes: Int64?
    public var lastSeenAt: Date
}

public struct FileRecord: Codable, Identifiable, Hashable, Sendable, ScanSessionScoped {
    public var id: String
    public var scanSessionID: String
    public var source: FileSource
    public var url: URL
    public var displayPath: String
    public var fileName: String
    public var fileExtension: String?
    public var utiDescription: String?
    public var kind: FileKind
    public var sizeBytes: Int64
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var lastOpenedAt: Date?
    public var owner: String?
    public var permissions: String?
    public var isSymlink: Bool
    public var symlinkTarget: URL?
    public var isPackage: Bool
    public var isCloudPlaceholder: Bool
    public var cloudProvider: String?
    public var finderTags: [String]
    public var spotlightMetadata: [String: String]
    public var riskFlags: Set<RiskFlag>
    public var identity: FileIdentity
    public var capabilities: Set<ProviderCapability>
    /// Hard-link count from the crawl. Deleting one link of several frees nothing.
    public var linkCount: Int?
    /// Set on a summarized folder (see `FileCrawler.rollsUp`): the number of items
    /// below it. Its `sizeBytes` is then their total, and none of them has a record.
    public var rolledUpItemCount: Int?

    public init(
        id: String = UUID().uuidString,
        scanSessionID: String,
        source: FileSource,
        url: URL,
        displayPath: String,
        fileName: String,
        fileExtension: String?,
        utiDescription: String?,
        kind: FileKind,
        sizeBytes: Int64,
        createdAt: Date?,
        modifiedAt: Date?,
        lastOpenedAt: Date?,
        owner: String?,
        permissions: String?,
        isSymlink: Bool,
        symlinkTarget: URL?,
        isPackage: Bool,
        isCloudPlaceholder: Bool,
        cloudProvider: String?,
        finderTags: [String],
        spotlightMetadata: [String: String],
        riskFlags: Set<RiskFlag>,
        identity: FileIdentity,
        capabilities: Set<ProviderCapability>
    ) {
        self.id = id
        self.scanSessionID = scanSessionID
        self.source = source
        self.url = url
        self.displayPath = displayPath
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.utiDescription = utiDescription
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastOpenedAt = lastOpenedAt
        self.owner = owner
        self.permissions = permissions
        self.isSymlink = isSymlink
        self.symlinkTarget = symlinkTarget
        self.isPackage = isPackage
        self.isCloudPlaceholder = isCloudPlaceholder
        self.cloudProvider = cloudProvider
        self.finderTags = finderTags
        self.spotlightMetadata = spotlightMetadata
        self.riskFlags = riskFlags
        self.identity = identity
        self.capabilities = capabilities
    }

    public init(
        scanSessionID: String,
        url: URL,
        kind: FileKind = .regularFile,
        sizeBytes: Int64 = 0,
        source: FileSource = .local
    ) {
        self.id = UUID().uuidString
        self.scanSessionID = scanSessionID
        self.source = source
        self.url = url
        self.displayPath = url.path
        self.fileName = url.lastPathComponent
        self.fileExtension = url.pathExtension.isEmpty ? nil : url.pathExtension
        self.utiDescription = nil
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.createdAt = nil
        self.modifiedAt = nil
        self.lastOpenedAt = nil
        self.owner = nil
        self.permissions = nil
        self.isSymlink = false
        self.symlinkTarget = nil
        self.isPackage = false
        self.isCloudPlaceholder = false
        self.cloudProvider = nil
        self.finderTags = []
        self.spotlightMetadata = [:]
        self.riskFlags = []
        self.identity = FileIdentity(deviceIdentifier: nil, inodeIdentifier: nil, resourceIdentifier: nil)
        self.capabilities = []
    }
}

public enum HashStatus: String, Codable, Sendable {
    case failed
    case hashed
    case fullHashConfirmed
}

public struct FileFingerprint: Codable, Identifiable, Sendable {
    public var id: String { fileID }
    public var fileID: String
    public var sizeBytes: Int64
    public var quickHash: String?
    public var fullHash: String?
    public var imagePerceptualHash: String?
    public var videoKeyframeHashes: [String]
    public var hashStatus: HashStatus
}

public struct ContentSummary: Codable, Identifiable, Sendable {
    public var id: String { fileID }
    public var fileID: String
    public var textPreview: String?
    public var ocrText: String?
    public var language: String?
    public var detectedTopics: [String]
    public var imageLabels: [String]
    public var videoLabels: [String]
    public var privacyLevel: PrivacyMode
}

public struct ProjectUnit: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var rootURL: URL
    public var projectType: String
    public var confidence: Double
    public var lastActivityAt: Date?
    public var manifestFiles: [URL]
    public var sourceFilesCount: Int
    public var generatedFilesCount: Int
    public var totalBytes: Int64
    public var reclaimableBytes: Int64
    public var status: ProjectStatus
}

public struct RelationshipEdge: Codable, Identifiable, Sendable {
    public var id: String
    public var fromFileID: String
    public var toFileID: String
    public var edgeType: RelationshipEdgeType
    public var confidence: Double
    public var evidence: String
}

public struct Finding: Codable, Identifiable, Sendable, ScanSessionScoped {
    public var id: String
    public var scanSessionID: String
    public var category: FindingCategory
    public var severity: RiskLevel
    public var confidence: Double
    public var bytesReclaimable: Int64
    public var summary: String
    public var evidence: [String: String]
    public var targetFileIDs: [String]
}

public struct Recommendation: Codable, Identifiable, Sendable {
    public var id: String
    public var findingID: String
    public var actionType: ActionType
    public var targetFileIDs: [String]
    public var confidence: Double
    public var risk: RiskLevel
    public var reason: String
    public var expectedBytesReclaimed: Int64
    public var requiresConfirmation: Bool
    public var llmTraceID: String?
    public var policyTraceID: String?
    /// Reference location some actions need: `cloneDeduplicate` folds each
    /// target onto the keeper at this URL. Nil for all other actions.
    /// Optional so persisted recommendations decode when the field predates it.
    public var destination: URL? = nil
}

public struct Plan: Codable, Identifiable, Sendable, ScanSessionScoped {
    public var id: String
    public var scanSessionID: String
    public var createdAt: Date
    public var status: PlanStatus
    public var summary: String
    public var estimatedReclaimableBytes: Int64
    public var estimatedFilesAffected: Int
    public var riskBreakdown: [RiskLevel: Int]
    public var actions: [PlannedAction]
    /// Stores the actions before a natural-language command modified the plan, enabling undo of NL changes.
    public var originalActions: [PlannedAction]?

    public static func empty(sessionID: String) -> Plan {
        Plan(
            id: UUID().uuidString, scanSessionID: sessionID, createdAt: Date(), status: .proposed, summary: "",
            estimatedReclaimableBytes: 0, estimatedFilesAffected: 0, riskBreakdown: [:], actions: [])
    }
}

public struct PlannedAction: Codable, Identifiable, Sendable {
    public var id: String
    public var planID: String
    public var actionType: ActionType
    public var targets: [String]
    public var destination: URL?
    public var status: PlannedActionStatus
    public var risk: RiskLevel
    public var confidence: Double
    public var reason: String
    public var userDecision: UserDecision
    public var executedAt: Date?
    public var findingID: String?
    /// Set by the UI when the user explicitly confirms a high-risk destructive action.
    /// SafetyAuditor requires this flag (alongside `.approved`/`.alwaysDoThis`) before a
    /// high-risk destructive action may execute. Nil/false means no explicit confirmation.
    /// Optional so persisted plans decode when the field predates this flag.
    public var requiresExplicitConfirmation: Bool? = nil

    /// Explicit cross-module initializer. Memberwise init is internal-only, so
    /// the AppKit layer (and any out-of-module caller) needs this spelled out.
    public init(
        id: String,
        planID: String,
        actionType: ActionType,
        targets: [String],
        destination: URL? = nil,
        status: PlannedActionStatus,
        risk: RiskLevel,
        confidence: Double,
        reason: String,
        userDecision: UserDecision,
        executedAt: Date? = nil,
        findingID: String? = nil,
        requiresExplicitConfirmation: Bool? = nil
    ) {
        self.id = id
        self.planID = planID
        self.actionType = actionType
        self.targets = targets
        self.destination = destination
        self.status = status
        self.risk = risk
        self.confidence = confidence
        self.reason = reason
        self.userDecision = userDecision
        self.executedAt = executedAt
        self.findingID = findingID
        self.requiresExplicitConfirmation = requiresExplicitConfirmation
    }
}

public struct OperationLog: Codable, Identifiable, Sendable {
    public var id: String
    public var plannedActionID: String
    public var operationType: ActionType
    public var beforeState: [String: String]
    public var afterState: [String: String]
    public var executorVersion: String
    public var result: String
    public var error: String?
    public var timestamp: Date
}

public struct UndoRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var operationLogID: String
    public var inverseAction: ActionType
    public var restoreURL: URL?
    /// The current filesystem location of the item. For `.restore` inverse actions this is the Trash path;
    /// for `.move` inverse actions this is where the file was moved to (not the Trash).
    public var trashURL: URL?
    public var validUntil: Date?
    public var status: UndoStatus
}

public struct MemoryRule: Codable, Identifiable, Sendable {
    public var id: String
    public var scopeType: String
    public var scopeValue: String
    public var rule: String
    public var source: String
    public var confidence: Double
    public var createdAt: Date
    public var lastReinforcedAt: Date?
    /// Structured rule type for reliable matching. Nil for legacy rules (falls back to substring matching).
    public var ruleType: MemoryRuleType?
    /// The action type the rule was learned from. A rule only applies to
    /// candidate actions of the same type, so a "never" rule learned for one
    /// action type (e.g. moveToTrash) cannot over-suppress other action types
    /// (e.g. tag or archive). Nil for legacy or free-text calibration rules,
    /// which apply to all action types.
    public var actionType: ActionType? = nil
}

public enum MemoryRuleType: String, Codable, Sendable {
    case never
    case always
    case preferArchive
}

public struct RegretEvent: Codable, Identifiable, Sendable {
    public var id: String
    public var operationLogID: String
    public var restoredFileID: String
    public var reason: String
    public var createdAt: Date
    public var ruleAdjustments: [String]
}

public struct StorageSnapshot: Codable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var totalBytes: Int64
    public var bytesByCategory: [FindingCategory: Int64]
    public var bytesByRootPath: [String: Int64]
    public var bytesByProject: [String: Int64]
    public var removedBytesThroughApp: Int64
}

public struct PackageCleanupCandidate: Codable, Sendable {
    public var id: String
    public var title: String
    public var commandPath: URL
    public var arguments: [String]
    public var dryRunOutput: String
    public var risk: RiskLevel
    public var category: FindingCategory
    /// Space the tool reports it would free; nil when it cannot say.
    public var estimatedBytes: Int64?
    /// Process names that must not run during the command (e.g. Simulator).
    public var blockingProcesses: [String]?

    public init(
        id: String,
        title: String,
        commandPath: URL,
        arguments: [String],
        dryRunOutput: String,
        risk: RiskLevel,
        category: FindingCategory,
        estimatedBytes: Int64? = nil,
        blockingProcesses: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.commandPath = commandPath
        self.arguments = arguments
        self.dryRunOutput = dryRunOutput
        self.risk = risk
        self.category = category
        self.estimatedBytes = estimatedBytes
        self.blockingProcesses = blockingProcesses
    }
}

/// Immutable scan results. The mutable `Plan` is stored separately to avoid
/// copying the entire file array on every plan mutation (approve/reject/NL command).
public struct ScanOutcome: Codable, Sendable {
    public var session: ScanSession
    public var files: [FileRecord]
    public var fingerprints: [FileFingerprint]
    public var contentSummaries: [ContentSummary]
    public var projects: [ProjectUnit]
    public var edges: [RelationshipEdge]
    public var findings: [Finding]
    public var recommendations: [Recommendation]
    public var snapshot: StorageSnapshot
    public var packageCandidates: [PackageCleanupCandidate]

    /// An empty outcome for work that starts without a scan (an uninstall
    /// from the Applications list). Staged files and findings are appended.
    public static func standalone(session: ScanSession) -> ScanOutcome {
        ScanOutcome(
            session: session, files: [], fingerprints: [], contentSummaries: [], projects: [], edges: [],
            findings: [], recommendations: [],
            snapshot: StorageSnapshot(
                id: UUID().uuidString, createdAt: Date(), totalBytes: 0, bytesByCategory: [:], bytesByRootPath: [:],
                bytesByProject: [:], removedBytesThroughApp: 0),
            packageCandidates: [])
    }
}

public struct ProviderSettings: Codable, Sendable {
    public var providerName: String
    public var apiBaseURL: URL
    public var organizationID: String?
    public var projectID: String?
    public var textModel: String
    public var visionModel: String?
    public var embeddingModel: String?
    public var maxTokens: Int
    public var temperature: Double
    public var requestTimeoutSeconds: TimeInterval
    public var privacyMode: PrivacyMode

    public init(
        providerName: String = "OpenAI-compatible",
        apiBaseURL: URL = URL(string: "https://api.openai.com/v1", encodingInvalidCharacters: false) ?? URL(fileURLWithPath: "/"),
        organizationID: String? = nil,
        projectID: String? = nil,
        textModel: String = "gpt-4.1-mini",
        visionModel: String? = nil,
        embeddingModel: String? = nil,
        maxTokens: Int = 900,
        temperature: Double = 0.1,
        requestTimeoutSeconds: TimeInterval = 30,
        privacyMode: PrivacyMode = .localOnly
    ) {
        self.providerName = providerName
        self.apiBaseURL = apiBaseURL
        self.organizationID = organizationID
        self.projectID = projectID
        self.textModel = textModel
        self.visionModel = visionModel
        self.embeddingModel = embeddingModel
        self.maxTokens = max(1, min(maxTokens, 128_000))
        self.temperature = max(0, min(temperature, 2.0))
        self.requestTimeoutSeconds = max(1, requestTimeoutSeconds)
        self.privacyMode = privacyMode
    }
}
