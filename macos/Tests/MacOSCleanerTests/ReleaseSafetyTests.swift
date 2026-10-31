import XCTest
@testable import MacOSCleanerCore

/// Release-gate safety rails: developer signing state, Xcode archives, and the
/// real Trash are never reachable from tests or unattended cleanup.
final class ReleaseSafetyTests: XCTestCase {
    private let policy = PathSafetyPolicy()

    func testRealTrashRefusesToRunUnderXCTest() throws {
        let file = try TestFixtures.makeTemporaryDirectory().appendingPathComponent("keep.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertThrowsError(try FileSystemTrashProvider().trashItem(at: file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testKeychainAndSigningFilesAreProtectedAnywhere() {
        for path in ["/Users/me/Backups/login.keychain-db", "/Users/me/Downloads/Dist.provisionprofile", "/Users/me/AuthKey_ABC.p8"] {
            XCTAssertTrue(policy.isProtectedFromCleanup(url: URL(fileURLWithPath: path), isDirectory: false), path)
        }
    }

    /// Decisions only; nothing is read or changed.
    func testFoldersThatHoldProtectedDataAreRefused() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for path in ["Library/Developer/Xcode", "Library/Developer/CoreSimulator", "Library", ""] {
            let decision = policy.decide(target: home.appendingPathComponent(path), isDirectory: true)
            XCTAssertNotEqual(decision, .allow, path)
        }
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        XCTAssertEqual(policy.decide(target: derived, isDirectory: true), .allow)
    }

    func testFileProviderFoldersAreCloudPaths() {
        for path in ["/Users/me/Library/CloudStorage/GoogleDrive-me@x.com/My Drive/a.pdf",
            "/Users/me/Library/CloudStorage/Box-Box/a.pdf"] {
            XCTAssertNotNil(policy.cloudProvider(for: URL(fileURLWithPath: path)), path)
        }
    }

    func testXcodeUserDataSimulatorDevicesAndDeveloperPrefsAreProtected() {
        for path in [
            "/Users/me/Library/Developer/Xcode/UserData",
            "/Users/me/Library/Developer/Xcode/UserData/Provisioning Profiles/a.plist",
            "/Users/me/Library/Developer/CoreSimulator/Devices/ABC/data",
            "/Users/me/Library/Preferences/com.apple.dt.Xcode.plist"
        ] {
            XCTAssertTrue(policy.isProtectedFromCleanup(url: URL(fileURLWithPath: path), isDirectory: false), path)
        }
        let caches = URL(fileURLWithPath: "/Users/me/Library/Developer/CoreSimulator/Caches/dyld")
        XCTAssertFalse(policy.isProtectedFromCleanup(url: caches, isDirectory: true))
    }

    func testXcodeArchivesBecomeInspectOnlyInPlans() async {
        var record = TestFixtures.makeFileRecord(
            id: "archive", path: "/Users/me/Library/Developer/Xcode/Archives/2026-10-01/App.xcarchive", sizeBytes: 1_000)
        record.riskFlags = policy.riskFlags(for: record.url, isDirectory: true)
        XCTAssertTrue(record.riskFlags.contains(.reviewOnly))
        let recommendation = TestFixtures.makeRecommendation(id: "r", targetID: "archive", action: .moveToTrash, risk: .low)
        let plan = await PlannerAgent().makePlan(
            sessionID: "s", recommendations: [recommendation], filesByID: ["archive": record])
        XCTAssertEqual(plan.actions.first?.actionType, .inspectOnly)
        XCTAssertEqual(plan.actions.first?.risk, .high)
    }

    func testAuditorRejectsApprovedTrashOfAnArchive() async throws {
        let file = try TestFixtures.makeTemporaryDirectory().appendingPathComponent("Build.xcarchive")
        try Data("x".utf8).write(to: file)
        var record = TestFixtures.makeFileRecord(id: "a", path: file.path, sizeBytes: 1)
        if let identity = FileArtifactIdentity.capture(at: file) {
            record.identity = FileIdentity(
                deviceIdentifier: identity.deviceID, inodeIdentifier: identity.inodeID, resourceIdentifier: nil)
        }
        let action = PlannedAction(
            id: "act", planID: "p", actionType: .moveToTrash, targets: ["a"], status: .approved,
            risk: .low, confidence: 0.9, reason: "fixture", userDecision: .approved)
        do {
            _ = try await SafetyAuditor().audit(action: action, filesByID: ["a": record])
            XCTFail("Archives must never be trashed through a plan")
        } catch let error as SafetyAuditError {
            guard case .unsafePath = error else { return XCTFail("Expected unsafePath, got \(error)") }
        }
    }

    func testFilesUnderUserLibraryAreNeverDuplicateCandidates() {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        XCTAssertTrue(DuplicateDetector.isInsideUserLibrary(library.appendingPathComponent("Containers/x/a.jpg")))
        XCTAssertFalse(DuplicateDetector.isInsideUserLibrary(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/a.jpg")))
    }
}

final class TrashBinTests: XCTestCase {
    func testEmptyRemovesContentsButKeepsTheFolder() throws {
        let trash = try TestFixtures.makeTemporaryDirectory().appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: trash.appendingPathComponent("file.txt"))
        XCTAssertEqual(try TrashBin.empty(trashURL: trash), 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
    }

    func testEmptyRefusesFoldersThatAreNotTheTrash() throws {
        let root = try TestFixtures.makeTemporaryDirectory()
        let other = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: other.appendingPathComponent("keep.txt"))
        XCTAssertThrowsError(try TrashBin.empty(trashURL: other))
        let link = root.appendingPathComponent(".Trash")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        XCTAssertThrowsError(try TrashBin.empty(trashURL: link), "A symlink named .Trash must not be followed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.appendingPathComponent("keep.txt").path))
    }
}

final class FullDiskAccessTests: XCTestCase {
    func testProbesFallBackPastMissingFiles() throws {
        let home = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertFalse(FullDiskAccess.isGranted(home: home), "No probe exists: not granted")
        let bookmarks = home.appendingPathComponent("Library/Safari/Bookmarks.plist")
        try FileManager.default.createDirectory(at: bookmarks.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: bookmarks)
        XCTAssertTrue(FullDiskAccess.isGranted(home: home), "Missing TCC.db falls through to a readable probe")
        XCTAssertNil(FullDiskAccess.canOpen(home.appendingPathComponent("missing")))
    }
}

/// Constant-level release gates that must run in CI even though the
/// Vision-dependent suite they were extracted from is skipped headless.

/// Constant-level release gates that must run in CI even though the
/// Vision-dependent suite they were extracted from is skipped headless.

/// Constant-level release gates that must run in CI even though the
/// Vision-dependent suite they were extracted from is skipped headless.

final class NearDuplicateBoundsTests: XCTestCase {
    func testNearDuplicateThresholdSeparatesUnrelatedImages() {
        // About 1 for unrelated images on the current feature print; 8 matched every pair.
        XCTAssertLessThan(DuplicateDetector.nearDuplicateDistanceThreshold, 0.9)
    }

    func testNearDuplicateWorkIsBounded() {
        XCTAssertLessThanOrEqual(DuplicateDetector.maxNearDuplicateImages, 20_000)
        XCTAssertLessThanOrEqual(DuplicateDetector.nearDuplicateWindow, 64)
    }
}
