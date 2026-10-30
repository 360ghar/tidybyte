import Foundation
import XCTest
@testable import MacOSCleanerCore

/// Stand-in for the user's Trash. Tests must never touch the real one
/// (`FileSystemTrashProvider` refuses to run under XCTest).
struct FixtureTrash: TrashService {
    let folder: URL
    var shouldFail = false

    init(folder: URL = FixtureTrash.sharedFolder, shouldFail: Bool = false) {
        self.folder = folder
        self.shouldFail = shouldFail
    }

    /// One folder per test process instead of one per executor: ~490 tests
    /// otherwise litter TMPDIR with per-test dirs (OS-purged, but noisy).
    /// Collisions are handled per-item below, like the real Trash renames.
    private static let sharedFolder: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FixtureTrash-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func trashItem(at url: URL) throws -> URL? {
        if shouldFail { throw CleanupError.message("Fixture failure") }
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            // Same-named items get their own slot, like the real Trash renames them.
            let slot = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            destination = slot.appendingPathComponent(url.lastPathComponent)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

/// Fixture builders shared across test files. Previously copy-pasted as
/// private helpers in four suites; one canonical source now.
enum TestFixtures {
    static let privacyKeychain = KeychainStore(inMemory: true)
    static func makeTemporaryDirectory(named name: String = "MacCleanerTest-\(UUID().uuidString)") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeExecutor(store: SQLiteStore, auditor: SafetyAuditor = SafetyAuditor()) -> ActionExecutor {
        ActionExecutor(store: store, auditor: auditor, trash: FixtureTrash())
    }

    static func makeFileRecord(id: String, path: String, sizeBytes: Int64) -> FileRecord {
        let url = URL(fileURLWithPath: path)
        return FileRecord(
            id: id, scanSessionID: "test-scan", source: .local, url: url,
            displayPath: path, fileName: url.lastPathComponent,
            fileExtension: url.pathExtension, utiDescription: nil,
            kind: .regularFile, sizeBytes: sizeBytes,
            createdAt: Date(), modifiedAt: Date(), lastOpenedAt: nil,
            owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
            isPackage: false, isCloudPlaceholder: false, cloudProvider: nil,
            finderTags: [], spotlightMetadata: [:], riskFlags: [],
            identity: FileIdentity(deviceIdentifier: 1, inodeIdentifier: 1, resourceIdentifier: nil),
            capabilities: []
        )
    }

    static func makeRecommendation(id: String, targetID: String, action: ActionType, risk: RiskLevel, confidence: Double = 0.8) -> Recommendation {
        Recommendation(
            id: id, findingID: "finding-\(id)", actionType: action, targetFileIDs: [targetID],
            confidence: confidence, risk: risk, reason: "test reason",
            expectedBytesReclaimed: 0, requiresConfirmation: false,
            llmTraceID: nil, policyTraceID: nil
        )
    }
}

extension XCTestCase {
    /// Isolated defaults suite whose plist is removed when the test ends.
    func makeIsolatedDefaults() -> UserDefaults {
        let name = "TidybyteTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name) ?? UserDefaults()
    }
}
