import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Redesign regression tests: central Policy.decide gate, destination
/// validation, in-place-rewrite detection, batch caps, and stable file IDs.
final class RedesignSafetyTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Redesign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStore() throws -> SQLiteStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("redesign-\(UUID().uuidString).sqlite")
        return try SQLiteStore(databaseURL: url)
    }

    private func makeRecord(id: String, url: URL, size: Int64 = 1024) -> FileRecord {
        FileRecord(
            id: id, scanSessionID: "session", source: .local, url: url,
            displayPath: url.path, fileName: url.lastPathComponent,
            fileExtension: url.pathExtension, utiDescription: nil,
            kind: .regularFile, sizeBytes: size,
            createdAt: Date(), modifiedAt: Date(), lastOpenedAt: nil,
            owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
            isPackage: false, isCloudPlaceholder: false, cloudProvider: nil,
            finderTags: [], spotlightMetadata: [:], riskFlags: [],
            identity: FileArtifactIdentity.capture(at: url).map {
                FileIdentity(deviceIdentifier: $0.deviceID, inodeIdentifier: $0.inodeID, resourceIdentifier: nil, sizeBytes: size, modifiedAt: Date())
            } ?? FileIdentity(deviceIdentifier: 1, inodeIdentifier: 1, resourceIdentifier: nil, sizeBytes: size, modifiedAt: Date()),
            capabilities: []
        )
    }

    private func makeApprovedTrashAction(targets: [String]) -> PlannedAction {
        PlannedAction(
            id: "act-\(targets.joined())",
            planID: "plan",
            actionType: .moveToTrash,
            targets: targets,
            destination: nil,
            status: .approved,
            risk: .low,
            confidence: 0.9,
            reason: "redesign fixture",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )
    }

    func testCaseVariantProtectedFileNamesAreBlocked() {
        let policy = PathSafetyPolicy()
        for name in ["AGENTS.MD", ".ENV", "Claude.MD", "CONFIG.YAML", "ID_RSA"] {
            let flags = policy.riskFlags(for: URL(fileURLWithPath: "/tmp/proj/\(name)"), isDirectory: false)
            XCTAssertFalse(flags.isEmpty, "\(name) must be flagged regardless of case")
            XCTAssertEqual(policy.decide(target: URL(fileURLWithPath: "/tmp/proj/\(name)"), isDirectory: false), .deny(reason: "Protected path: /tmp/proj/\(name)"))
        }
    }

    func testCaseVariantManifestsFlagged() {
        let policy = PathSafetyPolicy()
        for name in ["PACKAGE.JSON", "Package.Swift", "DOCKERFILE", "Readme.MD"] {
            let flags = policy.riskFlags(for: URL(fileURLWithPath: "/tmp/proj/\(name)"), isDirectory: false)
            XCTAssertTrue(flags.contains(.projectManifest), "\(name) must be a manifest regardless of case")
        }
    }

    func testDestinationInsideTrashIsRejected() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.txt")
        try Data("x".utf8).write(to: file)
        let record = makeRecord(id: "t1", url: file)
        var action = makeApprovedTrashAction(targets: [record.id])
        action.actionType = .move
        action.destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/evil", isDirectory: true)
        do {
            _ = try await SafetyAuditor().audit(action: action, filesByID: [record.id: record])
            XCTFail("A move into the Trash must be rejected at audit time")
        } catch let error as SafetyAuditError {
            guard case .unsafeDestination = error else {
                return XCTFail("Expected unsafeDestination, got \(error)")
            }
        }
    }

    func testInPlaceRewriteFailsVerification() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes.txt")
        try Data("short".utf8).write(to: file)
        var record = makeRecord(id: "rw", url: file, size: 5)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        record.identity = FileIdentity(
            deviceIdentifier: (attrs[.systemNumber] as? NSNumber)?.uint64Value,
            inodeIdentifier: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
            resourceIdentifier: nil,
            sizeBytes: 5,
            modifiedAt: attrs[.modificationDate] as? Date
        )
        try await SafetyAuditor().verifyTargetUnchanged(record)
        try Data("a much longer rewritten content body".utf8).write(to: file)
        do {
            try await SafetyAuditor().verifyTargetUnchanged(record)
            XCTFail("An in-place rewrite (same inode, new bytes) must fail verification")
        } catch let error as SafetyAuditError {
            guard case .identityMismatch = error else {
                return XCTFail("Expected identityMismatch, got \(error)")
            }
        }
    }

    func testBatchActionCapRefusesOversizedBatches() async throws {
        let store = try makeStore()
        let executor = TestFixtures.makeExecutor(store: store)
        let actions = (0..<(ExecutionLimits.maxActionsPerBatch + 1)).map { index in
            PlannedAction(
                id: "a\(index)", planID: "p", actionType: .inspectOnly, targets: [],
                destination: nil, status: .proposed, risk: .low, confidence: 0.9,
                reason: "cap fixture", userDecision: .approved, executedAt: nil, findingID: nil
            )
        }
        let summary = await executor.execute(actions: actions, filesByID: [:])
        XCTAssertTrue(summary.failures.contains { $0.contains("Batch limit exceeded") })
        XCTAssertEqual(summary.failedActionIDs.count, actions.count)
        XCTAssertTrue(summary.logs.isEmpty)
    }

    func testStableFileIDsSurviveRescan() {
        let path = "/Users/me/Documents/report.pdf"
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        let first = StableFileID.forStandardizedPath(path, sizeBytes: 1024, modifiedAt: mtime)
        let second = StableFileID.forStandardizedPath(path, sizeBytes: 1024, modifiedAt: mtime)
        XCTAssertEqual(first, second)
        let edited = StableFileID.forStandardizedPath(path, sizeBytes: 2048, modifiedAt: mtime)
        XCTAssertNotEqual(first, edited)
        let otherPath = StableFileID.forStandardizedPath("/Users/me/Documents/other.pdf", sizeBytes: 1024, modifiedAt: mtime)
        XCTAssertNotEqual(first, otherPath)
    }

    func testHashCacheHitAndInvalidation() async throws {
        let store = try SQLiteStore.inMemory()
        let path = "/tmp/cached.bin"
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveFileHash(FileHashCacheEntry(path: path, sizeBytes: 100, modifiedAt: mtime, fullHash: "abc"))
        let hit = try await store.cachedFullHash(forPath: path, sizeBytes: 100, modifiedAt: mtime)
        let sizeMiss = try await store.cachedFullHash(forPath: path, sizeBytes: 200, modifiedAt: mtime)
        let mtimeMiss = try await store.cachedFullHash(forPath: path, sizeBytes: 100, modifiedAt: mtime.addingTimeInterval(60))
        XCTAssertEqual(hit, "abc")
        XCTAssertNil(sizeMiss)
        XCTAssertNil(mtimeMiss)
    }

    func testIntentParserGrammar() {
        XCTAssertEqual(IntentParser.parse("clean up remote files").action, .review, "substring 'remove' inside 'remote' must not trigger delete")
        XCTAssertEqual(IntentParser.parse("delete my caches").action, .delete)
        XCTAssertEqual(IntentParser.parse("archive old downloads").action, .archive)
        XCTAssertEqual(IntentParser.parse("organize my desktop").action, .organize)
        XCTAssertTrue(IntentParser.parse("show big files").scopes.contains(.largerThan(bytes: 1_000_000_000)))
        XCTAssertTrue(IntentParser.parse("clean duplicates").scopes.contains(.duplicates))
        XCTAssertTrue(IntentParser.parse("files older than 90 days").scopes.contains(.olderThan(days: 90)))
        XCTAssertTrue(IntentParser.parse("be safe").scopes.contains(.safeOnly))
        XCTAssertTrue(IntentParser.parse("show everything").scopes.contains(.restoreAll))
        XCTAssertTrue(IntentParser.parse("undo my filter").scopes.contains(.restoreAll))
        // "everything" only restores with review verbs: mutating commands keep
        // targeting every action instead of silently restoring the plan.
        XCTAssertEqual(IntentParser.parse("delete everything").action, .delete)
        XCTAssertFalse(IntentParser.parse("delete everything").scopes.contains(.restoreAll))
        XCTAssertEqual(IntentParser.parse("delete everything").scopes, [.all])
        XCTAssertFalse(IntentParser.parse("archive everything").scopes.contains(.restoreAll))
        // Installers get their own scope so they match in Desktop/Documents too.
        XCTAssertTrue(IntentParser.parse("old installers").scopes.contains(.oldInstallers(days: 30)))
        XCTAssertFalse(IntentParser.parse("old installers").scopes.contains { if case .oldDownloads = $0 { return true }; return false })
        XCTAssertTrue(IntentParser.parse("old downloads").scopes.contains(.oldDownloads(days: 30)))
        XCTAssertEqual(IntentParser.parse("hello world").scopes, [.all])
    }

    func testProjectEdgeFanOutIsCapped() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifestURL = root.appendingPathComponent("package.json")
        try Data("{}".utf8).write(to: manifestURL)
        var urls = [manifestURL]
        for index in 0..<500 {
            let fileURL = root.appendingPathComponent("src/file\(index).js")
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: fileURL)
            urls.append(fileURL)
        }
        let crawler = FileCrawler()
        let (files, _) = await crawler.crawl(rootURLs: [root], sessionID: "s")
        let detector = ProjectDetector()
        let projects = try await detector.detectProjects(in: files)
        XCTAssertFalse(projects.isEmpty, "Fixture must detect a project")
        let edges = await detector.buildEdges(files: files, projects: projects)
        for project in projects {
            let count = edges.filter { edge in
                project.manifestFiles.contains { manifest in edge.fromFileID.contains(manifest.lastPathComponent) }
                    || edge.evidence.contains(project.rootURL.path)
            }.count
            XCTAssertLessThanOrEqual(count, ProjectDetector.maxEdgesPerProject * max(1, project.manifestFiles.count))
        }
        XCTAssertLessThanOrEqual(ProjectDetector.maxEdgesPerProject, 200)
    }
}
