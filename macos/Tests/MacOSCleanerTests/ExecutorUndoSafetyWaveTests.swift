import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Review-wave tests (2026-08-01): executor per-target resilience, trash-identity
/// restore verification, undo sibling loading, undo purging, memory-rule
/// reinforcement (dedup), and auditor rejection of unsupported action types.
final class ExecutorUndoSafetyWaveTests: XCTestCase {
    private func makeTemporaryDirectory(named prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeApprovedAction(id: String, type: ActionType, targets: [String], destination: URL? = nil) -> PlannedAction {
        PlannedAction(
            id: id,
            planID: "plan-wave",
            actionType: type,
            targets: targets,
            destination: destination,
            status: .approved,
            risk: .low,
            confidence: 0.9,
            reason: "wave test",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )
    }

    private func makeRecord(url: URL) -> FileRecord {
        FileRecord(
            scanSessionID: "wave",
            url: url,
            kind: .regularFile,
            sizeBytes: 1,
            source: .local
        )
    }

    // MARK: - Executor per-target resilience (tag/createAlias must not abort the whole action)

    func testTagContinuesAfterOneTargetVanished() async throws {
        let root = try makeTemporaryDirectory(named: "wave-tag")
        defer { try? FileManager.default.removeItem(at: root) }
        let validURL = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: validURL)
        let vanishedURL = root.appendingPathComponent("vanished.txt")
        try Data("gone".utf8).write(to: vanishedURL)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "wave")
        let validRecord = try XCTUnwrap(records.first { $0.url == validURL.standardizedFileURL })
        let vanishedRecord = try XCTUnwrap(records.first { $0.url == vanishedURL.standardizedFileURL })
        try FileManager.default.removeItem(at: vanishedURL)

        let store = try SQLiteStore.inMemory()
        let executor = TestFixtures.makeExecutor(store: store)
        let action = makeApprovedAction(id: "tag-action", type: .tag, targets: [validRecord.id, vanishedRecord.id])
        let summary = await executor.execute(
            actions: [action],
            filesByID: [validRecord.id: validRecord, vanishedRecord.id: vanishedRecord]
        )

        XCTAssertEqual(summary.logs.count, 1, "Valid target must still be tagged when another target vanished")
        XCTAssertEqual(summary.failures.count, 1, "Vanished target should be reported as a per-target failure")
        XCTAssertTrue(summary.failedActionIDs.contains(action.id), "Partial failure marks the action failed")
    }

    func testCreateAliasContinuesAfterOneTargetVanished() async throws {
        let root = try makeTemporaryDirectory(named: "wave-alias")
        defer { try? FileManager.default.removeItem(at: root) }
        let validURL = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: validURL)
        let vanishedURL = root.appendingPathComponent("vanished.txt")
        try Data("gone".utf8).write(to: vanishedURL)
        let aliasesDir = root.appendingPathComponent("Aliases", isDirectory: true)
        try FileManager.default.createDirectory(at: aliasesDir, withIntermediateDirectories: true)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "wave")
        let validRecord = try XCTUnwrap(records.first { $0.url == validURL.standardizedFileURL })
        let vanishedRecord = try XCTUnwrap(records.first { $0.url == vanishedURL.standardizedFileURL })
        try FileManager.default.removeItem(at: vanishedURL)

        let store = try SQLiteStore.inMemory()
        let executor = TestFixtures.makeExecutor(store: store)
        let action = makeApprovedAction(
            id: "alias-action",
            type: .createAlias,
            targets: [validRecord.id, vanishedRecord.id],
            destination: aliasesDir
        )
        let summary = await executor.execute(
            actions: [action],
            filesByID: [validRecord.id: validRecord, vanishedRecord.id: vanishedRecord]
        )

        XCTAssertEqual(summary.logs.count, 1, "Valid target must still be aliased when another target vanished")
        XCTAssertEqual(summary.failures.count, 1)

    }

    // MARK: - Restore identity verification

    func testRestoreRefusesOnTrashIdentityMismatch() async throws {
        let root = try makeTemporaryDirectory(named: "wave-restore")
        defer { try? FileManager.default.removeItem(at: root) }
        let trashURL = root.appendingPathComponent("in-trash.bin")
        try Data("payload".utf8).write(to: trashURL)
        let restoreURL = root.appendingPathComponent("restored.bin")
        // A different file's identity: simulates the recorded trash path now
        // holding a swapped file.
        let decoyURL = root.appendingPathComponent("decoy.bin")
        try Data("decoy".utf8).write(to: decoyURL)
        let decoyIdentity = try XCTUnwrap(FileArtifactIdentity.capture(at: decoyURL))
        let identityString = try XCTUnwrap(decoyIdentity.encodedString)

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let log = OperationLog(
            id: "log-1",
            plannedActionID: "action-1",
            operationType: .moveToTrash,
            beforeState: ["path": "/original.bin"],
            afterState: ["trash_identity": identityString],
            executorVersion: "test",
            result: "moved_to_trash",
            error: nil,
            timestamp: Date()
        )
        try await store.saveOperationLog(log)
        let undo = UndoRecord(
            id: "undo-1",
            operationLogID: log.id,
            inverseAction: .restore,
            restoreURL: restoreURL,
            trashURL: trashURL,
            validUntil: Date().addingTimeInterval(3600),
            status: .available
        )
        try await store.saveUndoRecord(undo)
        let service = UndoManagerService(store: store, memory: memory)

        do {
            _ = try await service.restore(undo)
            XCTFail("Restore must refuse when the trash item identity does not match")
        } catch let error as UndoManagerServiceError {
            guard case .trashArtifactIdentityMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: restoreURL.path))
    }

    func testRestoreSucceedsWhenTrashIdentityMatches() async throws {
        let root = try makeTemporaryDirectory(named: "wave-restore-ok")
        defer { try? FileManager.default.removeItem(at: root) }
        let trashURL = root.appendingPathComponent("in-trash.bin")
        try Data("payload".utf8).write(to: trashURL)
        let restoreURL = root.appendingPathComponent("restored.bin")
        let identity = try XCTUnwrap(FileArtifactIdentity.capture(at: trashURL))
        let identityString = try XCTUnwrap(identity.encodedString)

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let log = OperationLog(
            id: "log-ok",
            plannedActionID: "action-ok",
            operationType: .moveToTrash,
            beforeState: ["path": "/original.bin"],
            afterState: ["trash_identity": identityString],
            executorVersion: "test",
            result: "moved_to_trash",
            error: nil,
            timestamp: Date()
        )
        try await store.saveOperationLog(log)
        let undo = UndoRecord(
            id: "undo-ok",
            operationLogID: log.id,
            inverseAction: .restore,
            restoreURL: restoreURL,
            trashURL: trashURL,
            validUntil: Date().addingTimeInterval(3600),
            status: .available
        )
        try await store.saveUndoRecord(undo)
        let service = UndoManagerService(store: store, memory: memory)

        let restored = try await service.restore(undo)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoreURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashURL.path))
    }


    // MARK: - Undo sibling loading + purging

    func testLoadUndoRecordsByOperationLogReturnsOnlySiblings() async throws {
        let store = try SQLiteStore.inMemory()
        try await store.saveUndoRecord(UndoRecord(id: "u1", operationLogID: "logA", inverseAction: .restore, restoreURL: nil, trashURL: nil, validUntil: nil, status: .available))
        try await store.saveUndoRecord(UndoRecord(id: "u2", operationLogID: "logA", inverseAction: .moveToTrash, restoreURL: nil, trashURL: nil, validUntil: nil, status: .available))
        try await store.saveUndoRecord(UndoRecord(id: "u3", operationLogID: "logB", inverseAction: .restore, restoreURL: nil, trashURL: nil, validUntil: nil, status: .available))

        let siblings = try await store.loadUndoRecords(operationLogID: "logA")
        XCTAssertEqual(Set(siblings.map(\.id)), ["u1", "u2"])
    }

    func testPurgeRemovesExpiredUndoRecordsAndKeepsLiveOnes() async throws {
        let store = try SQLiteStore.inMemory()
        try await store.saveUndoRecord(UndoRecord(id: "expired-1", operationLogID: "l1", inverseAction: .restore, restoreURL: nil, trashURL: nil, validUntil: nil, status: .expired))
        try await store.saveUndoRecord(UndoRecord(id: "failed-1", operationLogID: "l2", inverseAction: .restore, restoreURL: nil, trashURL: nil, validUntil: nil, status: .failed))
        try await store.saveUndoRecord(UndoRecord(id: "past-1", operationLogID: "l3", inverseAction: .restore, restoreURL: nil, trashURL: nil, validUntil: Date().addingTimeInterval(-60), status: .available))
        let liveLog = OperationLog(
            id: "l4",
            plannedActionID: "a4",
            operationType: .moveToTrash,
            beforeState: [:],
            afterState: [:],
            executorVersion: "test",
            result: "ok",
            error: nil,
            timestamp: Date()
        )
        try await store.saveOperationLog(liveLog)
        try await store.saveUndoRecord(UndoRecord(id: "live-1", operationLogID: "l4", inverseAction: .restore, restoreURL: nil, trashURL: nil, validUntil: Date().addingTimeInterval(3600), status: .available))

        try await store.purgeOldData()

        let remaining = try await store.loadUndoRecords()
        XCTAssertEqual(remaining.map(\.id), ["live-1"], "Expired/failed/past-validity records must be purged; live ones kept")
        let survivingLog = try await store.loadOperationLog(id: "l4")
        XCTAssertNotNil(survivingLog, "Live operation log must survive the purge")
    }

    // MARK: - Memory rule reinforcement

    func testMemoryLearnReinforcesInsteadOfDuplicating() async throws {
        let root = try makeTemporaryDirectory(named: "wave-memory")
        defer { try? FileManager.default.removeItem(at: root) }
        let urlA = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: urlA)
        let urlB = root.appendingPathComponent("b.txt")
        try Data("b".utf8).write(to: urlB)

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        var firstAction = makeApprovedAction(id: "learn-1", type: .tag, targets: [urlA.path])
        firstAction.userDecision = .alwaysDoThis
        try await memory.learn(from: firstAction, filesByID: [urlA.path: makeRecord(url: urlA)])
        var secondAction = makeApprovedAction(id: "learn-2", type: .tag, targets: [urlB.path])
        secondAction.userDecision = .alwaysDoThis
        try await memory.learn(from: secondAction, filesByID: [urlB.path: makeRecord(url: urlB)])

        let rules = try await store.loadMemoryRules()
        XCTAssertEqual(rules.count, 1, "Same scope + action type + rule type must reinforce, not duplicate")
        XCTAssertNotNil(rules.first?.lastReinforcedAt, "Reinforced rule must carry a reinforcement timestamp")
    }

    // MARK: - Auditor unsupported actions

    func testAuditorRejectsRunProviderCleanupAsUnsupported() async throws {
        let auditor = SafetyAuditor()
        let action = makeApprovedAction(id: "provider-1", type: .runProviderCleanup, targets: [])
        do {
            _ = try await auditor.audit(action: action, filesByID: [:])
            XCTFail("Expected unsupportedAction rejection")
        } catch let error as SafetyAuditError {
            guard case .unsupportedAction = error else {
                return XCTFail("Unexpected error: \(error)")
}
        }
    }
}
