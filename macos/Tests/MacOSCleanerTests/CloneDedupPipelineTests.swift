import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Clone-dedup pipeline tests: planner resolution actions, auditor gates, and
/// the executor → undo round trip against real files on this APFS volume.
final class CloneDedupPipelineTests: XCTestCase {
    // MARK: - Planner + Auditor + Executor + Undo

    func testPlannerBuildsCloneResolutionActions() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("plan me".utf8)
        // Stagger creation so k.txt is newest and wins the keeper slot.
        let duplicate = try makeFile("d.txt", in: root, content: content)
        Thread.sleep(forTimeInterval: 0.05)
        let keeper = try makeFile("k.txt", in: root, content: content)
        let keeperCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: keeper))
        let duplicateCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: duplicate))
        let keeperRecord = record(id: "k", for: keeper, device: keeperCaptured.deviceID, inode: keeperCaptured.inodeID)
        let duplicateRecord = record(
            id: "d", for: duplicate, device: duplicateCaptured.deviceID, inode: duplicateCaptured.inodeID
        )
        let finding = Finding(
            id: "f1", scanSessionID: "s", category: .duplicate, severity: .low,
            confidence: 0.99, bytesReclaimable: duplicateRecord.sizeBytes,
            summary: "2 exact duplicate files", evidence: ["kept_file": keeper.path],
            targetFileIDs: [keeperRecord.id, duplicateRecord.id]
        )

        let cloneActions = PlannerAgent.duplicateResolutionActions(
            for: finding, filesByID: [keeperRecord.id: keeperRecord, duplicateRecord.id: duplicateRecord],
            strategy: .apfsClone, planID: "p"
        )
        XCTAssertEqual(cloneActions.count, 1)
        XCTAssertEqual(cloneActions[0].actionType, .cloneDeduplicate)
        XCTAssertEqual(cloneActions[0].targets, [duplicateRecord.id])
        XCTAssertEqual(cloneActions[0].destination?.path, keeper.path)
        XCTAssertEqual(cloneActions[0].risk, .low)

        let trashActions = PlannerAgent.duplicateResolutionActions(
            for: finding, filesByID: [keeperRecord.id: keeperRecord, duplicateRecord.id: duplicateRecord],
            strategy: .moveToTrash, planID: "p"
        )
        XCTAssertEqual(trashActions.count, 1)
        XCTAssertEqual(trashActions[0].actionType, .moveToTrash)
        XCTAssertNil(trashActions[0].destination)
    }

    func testAuditorRejectsCloneWithoutKeeperAndCloudTargets() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("k.txt", in: root, content: Data("x".utf8))
        let duplicate = try makeFile("d.txt", in: root, content: Data("x".utf8))
        let captured = try XCTUnwrap(FileArtifactIdentity.capture(at: duplicate))
        let duplicateRecord = record(id: "d", for: duplicate, device: captured.deviceID, inode: captured.inodeID)
        let auditor = SafetyAuditor()

        // No destination: the action names no keeper.
        let noKeeper = PlannedAction(
            id: "a1", planID: "p", actionType: .cloneDeduplicate, targets: [duplicateRecord.id],
            status: .proposed, risk: .low, confidence: 0.99, reason: "test",
            userDecision: .approved, findingID: nil
        )
        do {
            _ = try await auditor.audit(action: noKeeper, filesByID: [duplicateRecord.id: duplicateRecord])
            XCTFail("Clone without a keeper must be rejected")
        } catch let error as SafetyAuditError {
            guard case .missingKeeper = error else { return XCTFail("Unexpected error: \(error)") }
        }

        // Cloud-synced targets are rejected even with a keeper.
        var cloudRecord = duplicateRecord
        cloudRecord.cloudProvider = "Dropbox"
        let keeperCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: keeper))
        let keeperRecord = record(id: "k", for: keeper, device: keeperCaptured.deviceID, inode: keeperCaptured.inodeID)
        let withKeeper = PlannedAction(
            id: "a2", planID: "p", actionType: .cloneDeduplicate, targets: [cloudRecord.id],
            destination: keeper, status: .proposed, risk: .low, confidence: 0.99, reason: "test",
            userDecision: .approved, findingID: nil
        )
        do {
            _ = try await auditor.audit(
                action: withKeeper,
                filesByID: [cloudRecord.id: cloudRecord, keeperRecord.id: keeperRecord]
            )
            XCTFail("Clone of a cloud-synced file must be rejected")
        } catch let error as SafetyAuditError {
            guard case .cloudSideEffect = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testExecutorFoldsAndUndoRestores() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("fold me".utf8)
        let keeper = try makeFile("keeper.txt", in: root, content: content)
        let duplicate = try makeFile("duplicate.txt", in: root, content: content)
        let keeperCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: keeper))
        let duplicateCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: duplicate))
        let keeperRecord = record(id: "k", for: keeper, device: keeperCaptured.deviceID, inode: keeperCaptured.inodeID)
        let duplicateRecord = record(
            id: "d", for: duplicate, device: duplicateCaptured.deviceID, inode: duplicateCaptured.inodeID
        )
        var action = PlannedAction(
            id: "a1", planID: "p", actionType: .cloneDeduplicate, targets: [duplicateRecord.id],
            destination: keeper, status: .proposed, risk: .low, confidence: 0.99,
            reason: "test", userDecision: .approved, findingID: nil
        )
        action.status = .approved

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let executor = TestFixtures.makeExecutor(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        let summary = await executor.execute(
            actions: [action], filesByID: [keeperRecord.id: keeperRecord, duplicateRecord.id: duplicateRecord]
        )
        XCTAssertTrue(summary.failures.isEmpty, "Execution failures: \(summary.failures)")
        let undo = try XCTUnwrap(summary.undoRecords.first)
        XCTAssertEqual(undo.inverseAction, .unfoldClone)
        XCTAssertEqual(undo.status, .available)
        XCTAssertNil(undo.validUntil, "Clone undo never expires")
        XCTAssertEqual(summary.logs.first?.afterState["keeper_path"], keeper.path)
        XCTAssertNotNil(summary.logs.first?.afterState["clone_identity"])

        // The fold happened on disk.
        XCTAssertEqual(try Data(contentsOf: duplicate), content)
        let foldedInode = try identity(of: duplicate).inode
        XCTAssertNotEqual(foldedInode, duplicateCaptured.inodeID)

        // Undo gives the file its own storage back.
        let restored = try await undoService.restore(undo)
        XCTAssertEqual(restored.status, .restored)
        let unfoldedInode = try identity(of: duplicate).inode
        XCTAssertNotEqual(unfoldedInode, foldedInode)
        XCTAssertEqual(try Data(contentsOf: duplicate), content)
        XCTAssertEqual(try Data(contentsOf: keeper), content)
    }

    func testUndoSurvivesKeeperDeletion() async throws {
        // The keeper path is context on a fold record, not a dependency:
        // deleting the keeper after a fold must not kill the duplicate's undo.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("independent undo".utf8)
        let duplicate = try makeFile("duplicate.txt", in: root, content: content)
        try await Task.sleep(for: .milliseconds(50))
        let keeper = try makeFile("keeper.txt", in: root, content: content)
        let keeperCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: keeper))
        let duplicateCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: duplicate))
        let keeperRecord = record(id: "k", for: keeper, device: keeperCaptured.deviceID, inode: keeperCaptured.inodeID)
        let duplicateRecord = record(id: "d", for: duplicate, device: duplicateCaptured.deviceID, inode: duplicateCaptured.inodeID)
        var action = PlannedAction(
            id: "a1", planID: "p", actionType: .cloneDeduplicate, targets: [duplicateRecord.id],
            destination: keeper, status: .approved, risk: .low, confidence: 0.99,
            reason: "test", userDecision: .approved, findingID: nil
        )
        action.status = .approved

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let executor = TestFixtures.makeExecutor(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        let summary = await executor.execute(
            actions: [action], filesByID: [keeperRecord.id: keeperRecord, duplicateRecord.id: duplicateRecord]
        )
        XCTAssertTrue(summary.failures.isEmpty, "Execution failures: \(summary.failures)")
        let undo = try XCTUnwrap(summary.undoRecords.first)

        // The user deletes the keeper after folding.
        try FileManager.default.removeItem(at: keeper)

        let restored = try await undoService.restore(undo)
        XCTAssertEqual(restored.status, .restored, "Fold undo must not depend on the keeper existing")
        XCTAssertEqual(try Data(contentsOf: duplicate), content)
    }

    func testExecutorFailsSafelyWhenStorageIdentityChangedSinceScan() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.txt", in: root, content: Data("hardlinked".utf8))
        let twin = root.appendingPathComponent("twin.txt")
        try FileManager.default.linkItem(at: keeper, to: twin)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: twin.path
        )
        // Simulate a stale scan: the record claims a different inode than the
        // twin really has (they are hard links sharing one inode). The
        // mutation-time identity check must fail closed instead of folding.
        let keeperCaptured = try XCTUnwrap(FileArtifactIdentity.capture(at: keeper))
        var twinRecord = record(id: "t", for: twin, device: keeperCaptured.deviceID, inode: keeperCaptured.inodeID)
        twinRecord.identity = FileIdentity(
            deviceIdentifier: keeperCaptured.deviceID, inodeIdentifier: keeperCaptured.inodeID + 1,
            resourceIdentifier: nil, sizeBytes: twinRecord.sizeBytes, modifiedAt: twinRecord.modifiedAt
        )
        let keeperRecord = record(id: "k", for: keeper, device: keeperCaptured.deviceID, inode: keeperCaptured.inodeID)
        let action = PlannedAction(
            id: "a1", planID: "p", actionType: .cloneDeduplicate, targets: [twinRecord.id],
            destination: keeper, status: .approved, risk: .low, confidence: 0.99,
            reason: "test", userDecision: .approved, findingID: nil
        )

        let store = try SQLiteStore.inMemory()
        let executor = TestFixtures.makeExecutor(store: store)
        let summary = await executor.execute(
            actions: [action], filesByID: [keeperRecord.id: keeperRecord, twinRecord.id: twinRecord]
        )
        XCTAssertFalse(summary.failures.isEmpty, "A stale identity must fail closed")
        XCTAssertTrue(summary.undoRecords.allSatisfy { $0.status != .available })
        XCTAssertEqual(try Data(contentsOf: twin), Data("hardlinked".utf8), "The file must be untouched")
    }

    // MARK: Helpers

    private func makeTemporaryDirectory(named prefix: String = "CloneDedupPipeline") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleaner-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ path: String, in root: URL, content: Data, backdate: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try content.write(to: url)
        if backdate {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: url.path
            )
        }
        return url
    }

    private func identity(of url: URL) throws -> (device: UInt64, inode: UInt64) {
        let captured = try XCTUnwrap(FileArtifactIdentity.capture(at: url))
        return (captured.deviceID, captured.inodeID)
    }

    private func record(id: String, for url: URL, device: UInt64, inode: UInt64) -> FileRecord {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes?[.modificationDate] as? Date
        return FileRecord(
            id: id, scanSessionID: "scan", source: .local, url: url,
            displayPath: url.path, fileName: url.lastPathComponent,
            fileExtension: url.pathExtension, utiDescription: nil,
            kind: .regularFile, sizeBytes: size,
            createdAt: modified, modifiedAt: modified, lastOpenedAt: nil,
            owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
            isPackage: false, isCloudPlaceholder: false, cloudProvider: nil,
            finderTags: [], spotlightMetadata: [:], riskFlags: [],
            identity: FileIdentity(
                deviceIdentifier: device, inodeIdentifier: inode,
                resourceIdentifier: nil, sizeBytes: size, modifiedAt: modified
            ),
            capabilities: []
        )
    }
}
