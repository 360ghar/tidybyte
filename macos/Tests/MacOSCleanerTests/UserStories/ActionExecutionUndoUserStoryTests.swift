import Foundation
@testable import MacOSCleanerCore
import XCTest

final class ActionExecutionUndoUserStoryTests: XCTestCase {
    func testExecuteRunsOnlyApprovedActionsAndUndoRestoresMovedFile() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "ExecutionUndo")
        defer { try? FileManager.default.removeItem(at: root) }

        let approvedURL = try UserStoryFixtures.writeFile("reviewed-cache.bin", in: root)
        let undecidedURL = try UserStoryFixtures.writeFile("not-reviewed-cache.bin", in: root)
        let destination = try UserStoryFixtures.createDirectory("Destination", in: root)
        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let approvedRecord = try XCTUnwrap(records.first { $0.url == approvedURL.standardizedFileURL }, "Root: \(root.path); records: \(records.map(\.displayPath))")
        let undecidedRecord = try XCTUnwrap(records.first { $0.url == undecidedURL.standardizedFileURL })
        let filesByID = [approvedRecord.id: approvedRecord, undecidedRecord.id: undecidedRecord]
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("execution.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)
        let executor = TestFixtures.makeExecutor(store: store)
        let undo = UndoManagerService(store: store, memory: memory)

        let approved = PlannedAction(
            id: "approved-move",
            planID: "plan",
            actionType: .move,
            targets: [approvedRecord.id],
            destination: destination,
            status: .approved,
            risk: .low,
            confidence: 1,
            reason: "reviewed by user",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )
        let undecided = PlannedAction(
            id: "undecided-move",
            planID: "plan",
            actionType: .move,
            targets: [undecidedRecord.id],
            destination: destination,
            status: .proposed,
            risk: .low,
            confidence: 1,
            reason: "not reviewed",
            userDecision: .undecided,
            executedAt: nil,
            findingID: nil
        )

        let summary = await executor.execute(actions: [approved, undecided], filesByID: filesByID)

        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(summary.logs.map(\.plannedActionID), ["approved-move"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: approvedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("reviewed-cache.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: undecidedURL.path))

        let undoRecord = try XCTUnwrap(summary.undoRecords.first)
        let restored = try await undo.restore(undoRecord, regretReason: "Wrong file")
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: approvedURL.path))
    }

    func testProtectedOrHighRiskDestructiveActionsFailClosedAndLeaveFilesInPlace() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "FailClosed")
        defer { try? FileManager.default.removeItem(at: root) }

        let protectedURL = try UserStoryFixtures.writeFile(".env", in: root, data: Data("TOKEN=secret".utf8))
        let highRiskURL = try UserStoryFixtures.writeFile("Downloads/high-risk.txt", in: root)
        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let protectedRecord = try XCTUnwrap(records.first { $0.url == protectedURL.standardizedFileURL })
        let highRiskRecord = try XCTUnwrap(records.first { $0.url == highRiskURL.standardizedFileURL })
        let filesByID = [protectedRecord.id: protectedRecord, highRiskRecord.id: highRiskRecord]
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("fail-closed.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)

        let protectedAction = PlannedAction(
            id: "protected-trash",
            planID: "plan",
            actionType: .moveToTrash,
            targets: [protectedRecord.id],
            destination: nil,
            status: .approved,
            risk: .medium,
            confidence: 0.8,
            reason: "protected fixture",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )
        let highRiskAction = PlannedAction(
            id: "high-risk-trash",
            planID: "plan",
            actionType: .moveToTrash,
            targets: [highRiskRecord.id],
            destination: nil,
            status: .approved,
            risk: .high,
            confidence: 0.8,
            reason: "high risk fixture",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )

        let summary = await executor.execute(actions: [protectedAction, highRiskAction], filesByID: filesByID)

        XCTAssertEqual(summary.failedActionIDs, Set(["protected-trash", "high-risk-trash"]))
        XCTAssertEqual(summary.logs.count, 0)
        XCTAssertEqual(summary.undoRecords.count, 0)
        XCTAssertEqual(summary.failures.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: highRiskURL.path))
    }
}
