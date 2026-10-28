import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Wave 3A de-slop tests: fake feature implementations were removed from the
/// Core library. `.offloadLocalCopy` and `.runProviderCleanup` must now fail
/// with a typed error instead of pretending success or touching the
/// filesystem, and the merged move/rename executor path must keep working.
final class CoreDeSlopTests: XCTestCase {
    func makeTemporaryDirectory() throws -> URL {
        try TestFixtures.makeTemporaryDirectory()
    }

    /// Builds a FileRecord whose identity fields match the real file on disk
    /// (as the crawler would produce), so SafetyAuditor verifies it.
    private func makeRecord(id: String, url: URL) throws -> FileRecord {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileRecord(
            id: id,
            scanSessionID: "test-scan",
            source: .local,
            url: url,
            displayPath: url.path,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            utiDescription: nil,
            kind: .regularFile,
            sizeBytes: 0,
            createdAt: Date(),
            modifiedAt: Date(),
            lastOpenedAt: nil,
            owner: nil,
            permissions: nil,
            isSymlink: false,
            symlinkTarget: nil,
            isPackage: false,
            isCloudPlaceholder: false,
            cloudProvider: nil,
            finderTags: [],
            spotlightMetadata: [:],
            riskFlags: [],
            identity: FileIdentity(
                deviceIdentifier: (attrs[.systemNumber] as? NSNumber)?.uint64Value,
                inodeIdentifier: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
                resourceIdentifier: nil
            ),
            capabilities: []
        )
    }

    private func makeAction(id: String, type: ActionType, targets: [String], destination: URL?) -> PlannedAction {
        PlannedAction(
            id: id,
            planID: "plan",
            actionType: type,
            targets: targets,
            destination: destination,
            status: .approved,
            risk: .low,
            confidence: 1,
            reason: "de-slop test",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )
    }

    private func contentsOfDirectory(_ url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    // MARK: - Unsupported action types fail with a typed error

    func testOffloadLocalCopyFailsWithTypedErrorAndCreatesNoMarkers() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("offload-me.txt", isDirectory: false)
        try Data("precious contents".utf8).write(to: source)
        let record = try makeRecord(id: "offload-target", url: source)
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("test.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        let action = makeAction(id: "offload-action", type: .offloadLocalCopy, targets: [record.id], destination: nil)
        let baselineEntries = contentsOfDirectory(root)

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])

        // Typed failure surfaces in the summary, never a fake "success".
        XCTAssertEqual(
            summary.failures,
            [ActionExecutorError.unsupportedAction(.offloadLocalCopy).localizedDescription],
            "Offload must fail with the typed unsupportedAction error"
        )
        XCTAssertTrue(summary.failedActionIDs.contains("offload-action"))
        XCTAssertTrue(summary.undoRecords.isEmpty, "No undo record may be created for an unsupported action")
        XCTAssertTrue(summary.logs.isEmpty, "No operation log may be created for an unsupported action")

        // No marker file, no side effects: the directory is untouched and the file survives.
        XCTAssertEqual(contentsOfDirectory(root), baselineEntries, "No .offloaded marker or other file may be created")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "precious contents")
    }

    func testRunProviderCleanupFailsWithTypedErrorAndDoesNothing() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("provider-target.txt", isDirectory: false)
        try Data("provider data".utf8).write(to: source)
        let record = try makeRecord(id: "provider-target", url: source)
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("test.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        let action = makeAction(id: "provider-action", type: .runProviderCleanup, targets: [record.id], destination: nil)

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])

        XCTAssertEqual(
            summary.failures,
            [SafetyAuditError.unsupportedAction(.runProviderCleanup).localizedDescription],
            "Provider cleanup must be rejected at audit time with the typed unsupportedAction error (review-wave: rejected before the executor instead of after)"
        )
        XCTAssertTrue(summary.failedActionIDs.contains("provider-action"))
        XCTAssertTrue(summary.undoRecords.isEmpty)
        XCTAssertTrue(summary.logs.isEmpty, "No intent-only log may be created for an unsupported action")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "provider data")
    }

    // MARK: - Merged move/rename executor path

    func testMoveStillWorksAfterMoveRenameMerge() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("move-me.txt", isDirectory: false)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try Data("move".utf8).write(to: source)
        let record = try makeRecord(id: "move-target", url: source)
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("test.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        let action = makeAction(id: "move-action", type: .move, targets: [record.id], destination: destination)

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])

        XCTAssertTrue(summary.failures.isEmpty, "Move should succeed: \(summary.failures)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("move-me.txt", isDirectory: false).path))
        let undoRecord = try XCTUnwrap(summary.undoRecords.first)
        XCTAssertEqual(undoRecord.inverseAction, .move)
        XCTAssertEqual(undoRecord.restoreURL, source)
    }

    func testRenameStillWorksAfterMoveRenameMerge() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("old-name.txt", isDirectory: false)
        let destination = root.appendingPathComponent("Renamed", isDirectory: true)
        // Rename does not create the destination directory (unlike move); the caller provides it.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("rename".utf8).write(to: source)
        let record = try makeRecord(id: "rename-target", url: source)
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("test.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        let action = makeAction(id: "rename-action", type: .rename, targets: [record.id], destination: destination)

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])

        XCTAssertTrue(summary.failures.isEmpty, "Rename should succeed: \(summary.failures)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("old-name.txt", isDirectory: false).path))
        let undoRecord = try XCTUnwrap(summary.undoRecords.first)
        XCTAssertEqual(undoRecord.inverseAction, .rename)
        XCTAssertEqual(undoRecord.restoreURL, source)
    }

    func testMoveDeduplicatesCollidingNameAfterMerge() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("clash.txt", isDirectory: false)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try Data("original".utf8).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("already there".utf8).write(to: destination.appendingPathComponent("clash.txt", isDirectory: false))
        let record = try makeRecord(id: "clash-target", url: source)
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("test.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        let action = makeAction(id: "clash-action", type: .move, targets: [record.id], destination: destination)

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])

        XCTAssertTrue(summary.failures.isEmpty, "Collision-safe move should succeed: \(summary.failures)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("clash-1.txt", isDirectory: false).path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("clash.txt", isDirectory: false), encoding: .utf8), "already there")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("clash-1.txt", isDirectory: false), encoding: .utf8), "original")
    }

    // MARK: - Execution progress reporting

    private actor ProgressCollector {
        private var values: [Int] = []
        func append(_ value: Int) { values.append(value) }
        func snapshot() -> [Int] { values }
    }

    func testExecuteReportsPerActionProgress() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("first.txt", isDirectory: false)
        let secondURL = root.appendingPathComponent("second.txt", isDirectory: false)
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        let first = try makeRecord(id: "progress-1", url: firstURL)
        let second = try makeRecord(id: "progress-2", url: secondURL)
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("test.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        let actions = [
            makeAction(id: "progress-action-1", type: .move, targets: [first.id], destination: root.appendingPathComponent("D1", isDirectory: true)),
            makeAction(id: "progress-action-2", type: .move, targets: [second.id], destination: root.appendingPathComponent("D2", isDirectory: true)),
        ]
        let collector = ProgressCollector()

        let summary = await executor.execute(
            actions: actions,
            filesByID: [first.id: first, second.id: second],
            progress: { completed in
                await collector.append(completed)
            }
        )

        XCTAssertTrue(summary.failures.isEmpty, "Both moves should succeed: \(summary.failures)")
        let snapshot = await collector.snapshot()
        XCTAssertEqual(snapshot, [1, 2], "Progress must be reported once per completed action, in order")
    }
}
