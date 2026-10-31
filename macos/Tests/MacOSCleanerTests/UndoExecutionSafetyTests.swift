import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Wave 1A undo/execution safety tests:
/// - archive undo keeps the archive copy until the original is restored,
/// - restore never deletes an unrelated file at the restore location,
/// - parent directories are restored before children and recreated when missing,
/// - batch restore reports per-record failures with paths.
final class UndoExecutionSafetyTests: XCTestCase {
    private func makeTemporaryDirectory(named prefix: String = "UndoExecutionSafety") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleaner-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDirectory(_ relativePath: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeServices() throws -> (SQLiteStore, UndoManagerService) {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        return (store, UndoManagerService(store: store, memory: memory))
    }

    private func futureDate(days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    // MARK: Fix 1 — archive undo must keep the archive until the original is restored

    func testArchiveUndoKeepsArchiveWhenOriginalRestoreFails() async throws {
        let root = try makeTemporaryDirectory(named: "ArchiveGate")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, undoService) = try makeServices()

        let original = root.appendingPathComponent("report.pdf", isDirectory: false)
        try Data("original report".utf8).write(to: original)
        let archiveDir = try makeDirectory("Tidybyte Archive", in: root)
        let archive = archiveDir.appendingPathComponent("report.pdf-123.zip", isDirectory: false)
        try Data("zip content".utf8).write(to: archive)
        let trashDir = try makeDirectory("fake-trash", in: root)
        let trashCopy = trashDir.appendingPathComponent("report.pdf", isDirectory: false)
        // Simulate the real archive flow: the original is moved to the trash location.
        try FileManager.default.moveItem(at: original, to: trashCopy)

        let logID = "archive-log"
        var afterState: [String: String] = ["archive_path": archive.path, "trash_path": trashCopy.path]
        if let identity = FileArtifactIdentity.capture(at: archive) {
            afterState["artifact_identity"] = identity.encodedString
        }
        let log = OperationLog(
            id: logID, plannedActionID: "p1", operationType: .archive,
            beforeState: ["path": original.path, "file_id": "f1"],
            afterState: afterState,
            executorVersion: "1.0", result: "archived_and_moved_original_to_trash", error: nil, timestamp: Date()
        )
        try await store.saveOperationLog(log)
        let restoreUndo = UndoRecord(
            id: "restore-original", operationLogID: logID, inverseAction: .restore,
            restoreURL: original, trashURL: trashCopy,
            validUntil: futureDate(days: 30), status: .available
        )
        let archiveUndo = UndoRecord(
            id: "trash-archive", operationLogID: logID, inverseAction: .moveToTrash,
            restoreURL: archive, trashURL: nil, validUntil: nil, status: .available
        )
        try await store.saveUndoRecord(restoreUndo)
        try await store.saveUndoRecord(archiveUndo)

        // Archive undo before the original is restored: must fail and keep the archive.
        do {
            _ = try await undoService.restore(archiveUndo)
            XCTFail("Archive undo must fail while the original restore is still pending")
        } catch let error as UndoManagerServiceError {
            guard case .archiveOriginalNotRestored = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path), "Archive must be kept when the original restore has not completed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashCopy.path), "Original must still be at the trash location")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))

        // Restore the original, then the archive undo succeeds and deletes the archive.
        let restored = try await undoService.restore(restoreUndo)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original report")

        let done = try await undoService.restore(archiveUndo)
        XCTAssertEqual(done.status, .restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path), "Archive should be deleted after the original is restored")
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Original must survive the archive deletion")
    }

    // MARK: Fix 2 — restore never deletes an unrelated file at the restore location

    func testRestoreDoesNotDeleteUnrelatedFileAtRestoreURL() async throws {
        let root = try makeTemporaryDirectory(named: "IdentityCheck")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, undoService) = try makeServices()

        // Artifact created by the app (simulated alias).
        let artifact = root.appendingPathComponent("app.alias", isDirectory: false)
        try Data("alias data".utf8).write(to: artifact)
        let identity = try XCTUnwrap(FileArtifactIdentity.capture(at: artifact))
        // Keep the exact created inode alive via a hard link so the success path can
        // restore the very same artifact the record owns.
        let hardlink = root.appendingPathComponent("artifact-hardlink", isDirectory: false)
        try FileManager.default.linkItem(at: artifact, to: hardlink)

        let logID = "alias-log"
        let log = OperationLog(
            id: logID, plannedActionID: "p1", operationType: .createAlias,
            beforeState: ["path": "/tmp/original.txt"],
            afterState: ["alias_path": artifact.path, "artifact_identity": identity.encodedString ?? ""],
            executorVersion: "1.0", result: "alias_created", error: nil, timestamp: Date()
        )
        try await store.saveOperationLog(log)
        let undo = UndoRecord(
            id: "trash-artifact", operationLogID: logID, inverseAction: .moveToTrash,
            restoreURL: artifact, trashURL: nil, validUntil: nil, status: .available
        )
        try await store.saveUndoRecord(undo)

        // Replace the artifact with an unrelated user file (different inode).
        try FileManager.default.removeItem(at: artifact)
        let replacement = root.appendingPathComponent("user-notes.txt", isDirectory: false)
        try Data("precious user notes".utf8).write(to: replacement)
        try FileManager.default.moveItem(at: replacement, to: artifact)

        do {
            _ = try await undoService.restore(undo)
            XCTFail("Restore must refuse to delete an unrelated file at the restore location")
        } catch let error as UndoManagerServiceError {
            guard case .restoreArtifactIdentityMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.path), "Unrelated file must not be deleted")
        XCTAssertEqual(try String(contentsOf: artifact, encoding: .utf8), "precious user notes")

        // Put the exact created artifact back, then the same undo succeeds.
        try FileManager.default.removeItem(at: artifact)
        try FileManager.default.moveItem(at: hardlink, to: artifact)
        let restored = try await undoService.restore(undo)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path), "Owned artifact should be deleted on undo")
    }

    func testRestoreOfTrashedItemFailsWithoutDeletingUnrelatedDestination() async throws {
        let root = try makeTemporaryDirectory(named: "DestinationCheck")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, undoService) = try makeServices()

        let original = root.appendingPathComponent("notes.txt", isDirectory: false)
        let trashDir = try makeDirectory("fake-trash", in: root)
        let trashCopy = trashDir.appendingPathComponent("notes.txt", isDirectory: false)
        try Data("trashed content".utf8).write(to: trashCopy)
        // An unrelated file now occupies the restore destination.
        try Data("unrelated content".utf8).write(to: original)

        let undo = UndoRecord(
            id: "restore-notes", operationLogID: "log-notes", inverseAction: .restore,
            restoreURL: original, trashURL: trashCopy,
            validUntil: futureDate(days: 30), status: .available
        )
        try await store.saveUndoRecord(undo)

        do {
            _ = try await undoService.restore(undo)
            XCTFail("Restore must fail when an unrelated file occupies the destination")
        } catch let error as UndoManagerServiceError {
            guard case .restoreDestinationExists = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "unrelated content", "Unrelated destination file must be untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashCopy.path), "Trashed item must remain in place")
    }

    // MARK: Fix 3 — parent-before-child ordering and parent directory recreation

    func testBatchRestoreRestoresParentBeforeChild() async throws {
        let root = try makeTemporaryDirectory(named: "ParentChildOrdering")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, undoService) = try makeServices()

        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let child = project.appendingPathComponent("main.swift", isDirectory: false)
        try Data("print(\"hi\")".utf8).write(to: child)
        let trashDir = try makeDirectory("fake-trash", in: root)

        // Simulate two separate trash actions: one for the directory, one for the
        // file inside it, exactly like the plan can produce.
        let parentTrash = trashDir.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.moveItem(at: project, to: parentTrash)
        let childTrash = trashDir.appendingPathComponent("main.swift", isDirectory: false)
        try FileManager.default.moveItem(at: parentTrash.appendingPathComponent("main.swift", isDirectory: false), to: childTrash)

        let parentUndo = UndoRecord(
            id: "parent-undo", operationLogID: "log-parent", inverseAction: .restore,
            restoreURL: project, trashURL: parentTrash, validUntil: nil, status: .available
        )
        let childUndo = UndoRecord(
            id: "child-undo", operationLogID: "log-child", inverseAction: .restore,
            restoreURL: child, trashURL: childTrash, validUntil: nil, status: .available
        )
        try await store.saveUndoRecord(parentUndo)
        try await store.saveUndoRecord(childUndo)

        // Child passed first: the batch must still restore the parent first.
        let result = await undoService.restoreBatchDetailed([childUndo, parentUndo])
        XCTAssertTrue(result.failures.isEmpty, "Both records should restore, got failures: \(result.failures)")
        XCTAssertEqual(Set(result.restored.map(\.id)), Set(["parent-undo", "child-undo"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
        XCTAssertEqual(try String(contentsOf: child, encoding: .utf8), "print(\"hi\")")
    }

    func testSingleChildRestoreRecreatesMissingParentDirectory() async throws {
        let root = try makeTemporaryDirectory(named: "ParentRecreation")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, undoService) = try makeServices()

        let child = root.appendingPathComponent("project", isDirectory: true).appendingPathComponent("main.swift", isDirectory: false)
        let trashDir = try makeDirectory("fake-trash", in: root)
        let childTrash = trashDir.appendingPathComponent("main.swift", isDirectory: false)
        try Data("print(\"hi\")".utf8).write(to: childTrash)

        let childUndo = UndoRecord(
            id: "child-undo", operationLogID: "log-child", inverseAction: .restore,
            restoreURL: child, trashURL: childTrash, validUntil: nil, status: .available
        )
        try await store.saveUndoRecord(childUndo)

        let restored = try await undoService.restore(childUndo)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path), "Child must be restored with its parent directory recreated")
        XCTAssertEqual(try String(contentsOf: child, encoding: .utf8), "print(\"hi\")")
    }

    // MARK: Fix 3c — batch restore reports per-record failures with paths

    func testRestoreBatchReportsPerRecordFailuresWithPaths() async throws {
        let root = try makeTemporaryDirectory(named: "BatchFailures")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, undoService) = try makeServices()
        let trashDir = try makeDirectory("fake-trash", in: root)

        // Record 1: valid restore.
        let validFile = root.appendingPathComponent("valid.txt", isDirectory: false)
        try Data("valid".utf8).write(to: validFile)
        let validTrash = trashDir.appendingPathComponent("valid.txt", isDirectory: false)
        try FileManager.default.moveItem(at: validFile, to: validTrash)
        let validUndo = UndoRecord(
            id: "valid-undo", operationLogID: "log-valid", inverseAction: .restore,
            restoreURL: validFile, trashURL: validTrash, validUntil: nil, status: .available
        )
        try await store.saveUndoRecord(validUndo)

        // Record 2: expired undo.
        let expiredURL = root.appendingPathComponent("expired.txt", isDirectory: false)
        let expiredUndo = UndoRecord(
            id: "expired-undo", operationLogID: "log-expired", inverseAction: .restore,
            restoreURL: expiredURL, trashURL: nil,
            validUntil: futureDate(days: -1), status: .available
        )
        try await store.saveUndoRecord(expiredUndo)

        // Record 3: identity mismatch, the artifact was replaced by an unrelated file.
        let artifact = root.appendingPathComponent("app.alias", isDirectory: false)
        try Data("alias data".utf8).write(to: artifact)
        var afterState: [String: String] = ["alias_path": artifact.path]
        if let identity = FileArtifactIdentity.capture(at: artifact) {
            afterState["artifact_identity"] = identity.encodedString
        }
        let log = OperationLog(
            id: "log-alias", plannedActionID: "p1", operationType: .createAlias,
            beforeState: ["path": "/tmp/original.txt"],
            afterState: afterState,
            executorVersion: "1.0", result: "alias_created", error: nil, timestamp: Date()
        )
        try await store.saveOperationLog(log)
        let artifactUndo = UndoRecord(
            id: "mismatch-undo", operationLogID: "log-alias", inverseAction: .moveToTrash,
            restoreURL: artifact, trashURL: nil, validUntil: nil, status: .available
        )
        try await store.saveUndoRecord(artifactUndo)
        try FileManager.default.removeItem(at: artifact)
        let unrelated = root.appendingPathComponent("user.txt", isDirectory: false)
        try Data("precious".utf8).write(to: unrelated)
        try FileManager.default.moveItem(at: unrelated, to: artifact)

        let result = await undoService.restoreBatchDetailed([artifactUndo, validUndo, expiredUndo])

        XCTAssertEqual(Set(result.restored.map(\.id)), Set(["valid-undo"]))
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertEqual(result.failureCount, 2)

        let failureByID = Dictionary(uniqueKeysWithValues: result.failures.map { ($0.undoID, $0) })
        let expiredFailure = try XCTUnwrap(failureByID["expired-undo"], "Expired record must report a named failure")
        XCTAssertEqual(expiredFailure.restorePath, expiredURL.path)
        XCTAssertFalse(expiredFailure.errorDescription.isEmpty, "Failure must carry a reason")
        let mismatchFailure = try XCTUnwrap(failureByID["mismatch-undo"], "Mismatch record must report a named failure")
        XCTAssertEqual(mismatchFailure.restorePath, artifact.path)
        XCTAssertFalse(mismatchFailure.errorDescription.isEmpty, "Failure must carry a reason")

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.path), "Unrelated file must survive batch restore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: validFile.path), "Valid record must be restored")
    }
}
