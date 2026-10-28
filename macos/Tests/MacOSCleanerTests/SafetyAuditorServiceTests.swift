import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Safety auditor tests, split out of the former MacOSCleanerTests god file.
final class SafetyAuditorServiceTests: XCTestCase {

    // MARK: - SafetyAuditor Tests

    func testSafetyAuditorRejectsSymlinkDestructiveAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.txt", isDirectory: false)
        try Data("content".utf8).write(to: target)
        let symlink = root.appendingPathComponent("link.txt", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let linkRecord = try XCTUnwrap(records.first { $0.url == symlink.standardizedFileURL })
        XCTAssertTrue(linkRecord.isSymlink)

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: [linkRecord.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: [linkRecord.id: linkRecord])
            XCTFail("Expected symlink destructive action to be rejected")
        } catch let error as SafetyAuditError {
            guard case .symlinkTarget = error else {
                XCTFail("Expected symlinkTarget error, got: \(error)")
                return
            }
        }
    }

    func testSafetyAuditorRejectsCloudSyncedFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Create a file in a path that looks like iCloud
        let iCloudDir = root.appendingPathComponent("Mobile Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
        let file = iCloudDir.appendingPathComponent("doc.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == file.standardizedFileURL })
        XCTAssertNotNil(record.cloudProvider, "File in Mobile Documents should be detected as cloud-synced")

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: [record.id: record])
            XCTFail("Expected cloud-synced file to be rejected")
        } catch let error as SafetyAuditError {
            // Cloud-synced files are rejected — either by unsafePath (protected) or cloudSideEffect
            switch error {
            case .unsafePath(_, let flags):
                XCTAssertTrue(flags.contains(.cloudSyncedLocalPath), "Should have cloudSyncedLocalPath flag")
            case .cloudSideEffect:
                break // Also acceptable
            default:
                XCTFail("Expected unsafePath or cloudSideEffect, got: \(error)")
            }
        }
    }

    func testSafetyAuditorCollectsAllMissingTargets() async throws {
        let record = TestFixtures.makeFileRecord(id: "exists", path: "/tmp/exists.txt", sizeBytes: 100)
        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: ["missing1", "missing2", "exists"],
            destination: nil, status: .approved, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: [record.id: record])
            XCTFail("Expected missing target error")
        } catch let error as SafetyAuditError {
            guard case .missingTarget(let ids) = error else {
                XCTFail("Expected missingTarget error, got: \(error)")
                return
            }
            XCTAssertTrue(ids.contains("missing1"), "Should report missing1")
            XCTAssertTrue(ids.contains("missing2"), "Should report missing2")
        }
    }


    // MARK: - SafetyAuditor: Additional Checks (EX-15, EX-16, EX-17)

    func testSafetyAuditorAllowsApprovedAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("safe.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let auditor = SafetyAuditor()
        let result = try await auditor.audit(action: action, filesByID: [record.id: record])
        XCTAssertEqual(result.decision, .allowed)
    }

    func testSafetyAuditorRejectsUnapprovedAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("unapproved.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .proposed, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .undecided, executedAt: nil, findingID: nil
        )
        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: [record.id: record])
            XCTFail("Expected unapproved action to be rejected")
        } catch let error as SafetyAuditError {
            guard case .unapprovedAction = error else {
                XCTFail("Expected unapprovedAction error, got: \(error)")
                return
            }
        }
    }

    func testSafetyAuditorAllowsInspectOnly() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("inspect.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .inspectOnly, targets: [record.id],
            destination: nil, status: .proposed, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .undecided, executedAt: nil, findingID: nil
        )
        let auditor = SafetyAuditor()
        let result = try await auditor.audit(action: action, filesByID: [record.id: record])
        XCTAssertEqual(result.decision, .allowed)
    }


    // MARK: - SafetyAuditor: Identity Verification (EX-17)

    func testSafetyAuditorVerifiesFileIdentity() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("identity.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        // Verify the record has identity fields
        XCTAssertNotNil(record.identity.deviceIdentifier, "Should have device identifier")
        XCTAssertNotNil(record.identity.inodeIdentifier, "Should have inode identifier")

        let auditor = SafetyAuditor()
        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let result = try await auditor.audit(action: action, filesByID: [record.id: record])
        XCTAssertEqual(result.decision, .allowed, "File with matching identity should be allowed")
    }

    func testSafetyAuditorAllowsCrawledFolderAfterItsChildrenChange() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("a.bin"))

        let (records, _) = await FileCrawler().crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == folder.standardizedFileURL })
        // Apps keep writing into cache folders between scan and cleanup.
        try Data("b".utf8).write(to: folder.appendingPathComponent("b.bin"))

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let result = try await SafetyAuditor().audit(action: action, filesByID: [record.id: record])
        XCTAssertEqual(result.decision, .allowed)
    }


    // MARK: - SafetyAuditor: Fresh Symlink TOCTOU Detection (PS-10, EX-17)

    func testSafetyAuditorRejectsFileReplacedWithSymlinkAfterScan() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Create a regular file and scan it.
        let fileURL = root.appendingPathComponent("regular.txt", isDirectory: false)
        try Data("original".utf8).write(to: fileURL)
        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == fileURL.standardizedFileURL })
        XCTAssertFalse(record.isSymlink, "File should not be a symlink at scan time")

        // TOCTOU: replace the regular file with a symlink after scan but before audit.
        let protectedTarget = root.appendingPathComponent("secret.txt", isDirectory: false)
        try Data("secret".utf8).write(to: protectedTarget)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: protectedTarget)

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: [record.id: record])
            XCTFail("Expected symlinkTarget rejection for file replaced with symlink after scan")
        } catch let error as SafetyAuditError {
            // Either symlinkTarget (fresh detection) or identityMismatch (inode changed) is acceptable —
            // both fail safe. The key assertion is that the action is NOT allowed.
            switch error {
            case .symlinkTarget, .identityMismatch:
                break
            default:
                XCTFail("Expected symlinkTarget or identityMismatch, got: \(error)")
            }
        }
        // The symlink target must be untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedTarget.path))
    }

    func makeTemporaryDirectory() throws -> URL {
        try TestFixtures.makeTemporaryDirectory()
    }
}
