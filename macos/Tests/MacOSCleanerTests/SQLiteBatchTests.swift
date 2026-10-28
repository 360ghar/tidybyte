import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Tests for Wave 1D SQLite store robustness: batched (transactional) bulk
/// persistence, WAL-consistent database export, and idempotent migration on
/// existing databases.
final class SQLiteBatchTests: XCTestCase {
    private func makeTemporaryDirectory(named prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFileRecord(scanSessionID: String, index: Int) -> FileRecord {
        FileRecord(
            scanSessionID: scanSessionID,
            url: URL(fileURLWithPath: "/tmp/batch-test/file-\(index).bin"),
            kind: .regularFile,
            sizeBytes: Int64(index * 1024),
            source: .local
        )
    }

    func testBulkSaveFileRecordsPersistsEveryRowAndStaysReadable() async throws {
        let store = try SQLiteStore.inMemory()
        let sessionID = "batch-session"
        let count = 400
        let records = (0..<count).map { makeFileRecord(scanSessionID: sessionID, index: $0) }

        try await store.saveFileRecords(records)

        let loaded = try await store.loadFileRecords(for: sessionID)
        XCTAssertEqual(loaded.count, count, "All bulk-inserted records must be queryable after a batched insert")
        XCTAssertEqual(Set(loaded.map(\.id)).count, count, "Record IDs must be unique after a batched insert")
        XCTAssertEqual(Set(loaded.map(\.sizeBytes)), Set(records.map(\.sizeBytes)))
        let first = try XCTUnwrap(loaded.first { $0.fileName == "file-0.bin" })
        XCTAssertEqual(first.sizeBytes, 0)
        let last = try XCTUnwrap(loaded.first { $0.fileName == "file-399.bin" })
        XCTAssertEqual(last.sizeBytes, 399 * 1024)
    }

    func testSavePlanPersistsPlanAndAllActionsInOneBatch() async throws {
        let store = try SQLiteStore.inMemory()
        let planID = "plan-batch"
        let actions = (0..<250).map { index in
            PlannedAction(
                id: "action-\(index)",
                planID: planID,
                actionType: .moveToTrash,
                targets: ["file-\(index)"],
                status: .approved,
                risk: .low,
                confidence: 0.97,
                reason: "batch test",
                userDecision: .approved
            )
        }
        let plan = Plan(
            id: planID,
            scanSessionID: "plan-session",
            createdAt: Date(),
            status: .proposed,
            summary: "batch plan",
            estimatedReclaimableBytes: 1_000_000,
            estimatedFilesAffected: actions.count,
            riskBreakdown: [.low: actions.count],
            actions: actions
        )

        try await store.savePlan(plan)

        let loadedPlanValue = try await store.loadPlan(id: planID)
        let loadedPlan = try XCTUnwrap(loadedPlanValue)
        XCTAssertEqual(loadedPlan.summary, "batch plan")
        XCTAssertEqual(loadedPlan.actions.count, actions.count, "Plan and all actions must persist together")
        XCTAssertEqual(loadedPlan.actions.map(\.id).sorted(), actions.map(\.id).sorted())
    }

    func testBatchUndoRecordsAndOperationLogsPersist() async throws {
        let store = try SQLiteStore.inMemory()
        let undos = (0..<300).map { index in
            UndoRecord(
                id: "undo-\(index)",
                operationLogID: "log-\(index)",
                inverseAction: .moveToTrash,
                restoreURL: URL(fileURLWithPath: "/tmp/restored-\(index).bin"),
                trashURL: URL(fileURLWithPath: "/tmp/trash-\(index).bin"),
                status: .available
            )
        }
        let logs = (0..<300).map { index in
            OperationLog(
                id: "log-\(index)",
                plannedActionID: "action-\(index)",
                operationType: .moveToTrash,
                beforeState: ["path": "/tmp/before-\(index).bin"],
                afterState: ["path": "/tmp/trash-\(index).bin"],
                executorVersion: "test",
                result: "success",
                timestamp: Date()
            )
        }

        try await store.saveUndoRecords(undos)
        try await store.saveOperationLogs(logs)

        let loadedUndos = try await store.loadUndoRecords()
        XCTAssertEqual(loadedUndos.count, undos.count, "Batch-persisted undo records must all be queryable")
        XCTAssertEqual(Set(loadedUndos.map(\.id)), Set(undos.map(\.id)))
        let firstLogValue = try await store.loadOperationLog(id: "log-0")
        let firstLog = try XCTUnwrap(firstLogValue)
        XCTAssertEqual(firstLog.result, "success")
    }

    func testExportCopyProducesConsistentReadableSnapshot() async throws {
        let root = try makeTemporaryDirectory(named: "SQLiteBatchExport")
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("live.sqlite", isDirectory: false)
        let store = try SQLiteStore(databaseURL: databaseURL)
        let sessionID = "export-session"
        let count = 250
        let records = (0..<count).map { makeFileRecord(scanSessionID: sessionID, index: $0) }
        try await store.saveFileRecords(records)
        let planActions = (0..<10).map { index in
            PlannedAction(
                id: "export-action-\(index)",
                planID: "export-plan",
                actionType: .moveToTrash,
                targets: ["file-\(index)"],
                status: .approved,
                risk: .medium,
                confidence: 0.8,
                reason: "export test",
                userDecision: .approved
            )
        }
        try await store.savePlan(Plan(
            id: "export-plan",
            scanSessionID: sessionID,
            createdAt: Date(),
            status: .proposed,
            summary: "export plan",
            estimatedReclaimableBytes: 100,
            estimatedFilesAffected: 10,
            riskBreakdown: [.medium: 10],
            actions: planActions
        ))

        // File-backed stores run in WAL mode, so uncheckpointed rows live in the
        // -wal sidecar; exportCopy must capture them in the snapshot.
        let copyURL = root.appendingPathComponent("nested/exported.sqlite", isDirectory: false)
        try await store.exportCopy(to: copyURL)

        // A fresh connection over the copy must see every committed row.
        let copyStore = try SQLiteStore(databaseURL: copyURL)
        let copiedRecords = try await copyStore.loadFileRecords(for: sessionID)
        XCTAssertEqual(copiedRecords.count, count, "Exported snapshot must contain all committed rows, including WAL-resident ones")
        XCTAssertEqual(Set(copiedRecords.map(\.id)), Set(records.map(\.id)))
        let copiedPlanValue = try await copyStore.loadPlan(id: "export-plan")
        let copiedPlan = try XCTUnwrap(copiedPlanValue)
        XCTAssertEqual(copiedPlan.actions.count, 10, "Exported snapshot must include multiple tables")

        // Rows written after the export must not appear in the snapshot.
        try await store.saveFileRecords([makeFileRecord(scanSessionID: sessionID, index: 1000)])
        let copyAfterWrite = try await copyStore.loadFileRecords(for: sessionID)
        XCTAssertEqual(copyAfterWrite.count, count, "Exported snapshot must be isolated from later writes")

        // checkpointWAL must succeed on the live store without disturbing data.
        try await store.checkpointWAL()
        let afterCheckpoint = try await store.loadFileRecords(for: sessionID)
        XCTAssertEqual(afterCheckpoint.count, count + 1, "checkpointWAL must preserve all committed rows")
    }

    func testReopeningExistingDatabaseRunsIdempotentMigration() async throws {
        let root = try makeTemporaryDirectory(named: "SQLiteBatchReopen")
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("reopen.sqlite", isDirectory: false)
        do {
            let store = try SQLiteStore(databaseURL: databaseURL)
            try await store.saveFileRecords([makeFileRecord(scanSessionID: "s1", index: 1)])
        }

        // A fresh connection over the same file re-runs migration, which must be a
        // safe no-op on the existing database.
        let reopened = try SQLiteStore(databaseURL: databaseURL)
        let loaded = try await reopened.loadFileRecords(for: "s1")
        XCTAssertEqual(loaded.count, 1, "Reopening an existing database must preserve data and migration must be idempotent")
    }
}
