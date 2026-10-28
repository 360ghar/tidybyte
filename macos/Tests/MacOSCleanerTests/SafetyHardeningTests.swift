import XCTest
@testable import MacOSCleanerCore

/// Wave 1 safety regression tests: policy bypass closures, TOCTOU re-verification,
/// write-ahead undo trail, double-execution guard.
final class SafetyHardeningTests: XCTestCase {
    // MARK: - PathSafetyPolicy hardening

    func testCaseVariantSIPPathsAreProtected() {
        let policy = PathSafetyPolicy()
        for path in ["/SYSTEM/Library/test", "/Usr/Bin/tool", "/Private/etc/hosts"] {
            let flags = policy.riskFlags(for: URL(fileURLWithPath: path), isDirectory: false)
            XCTAssertTrue(flags.contains(.sipProtectedSystemPath), "\(path) must be SIP-protected regardless of case")
        }
    }

    func testCaseVariantProtectedDirectoriesMatch() {
        let policy = PathSafetyPolicy()
        for path in ["/Users/me/KEYCHAINS/x", "/Users/me/keychains/x", "/Users/me/MOBILESYNC/bak"] {
            let flags = policy.riskFlags(for: URL(fileURLWithPath: path), isDirectory: false)
            XCTAssertTrue(flags.contains(.protectedDirectory), "\(path) must match protected directory names case-insensitively")
        }
    }

    func testAppleManagedTempSpaceIsNotSIPFlagged() {
        let policy = PathSafetyPolicy()
        let url = URL(fileURLWithPath: FileManager.default.temporaryDirectory.appendingPathComponent("fixture.txt").path)
        let flags = policy.riskFlags(for: url, isDirectory: false)
        XCTAssertFalse(flags.contains(.sipProtectedSystemPath), "/var/folders temp space is Apple-managed per-user space, not system software")
    }

    func testHomeTrashContentsAreFlaggedAndSkipped() throws {
        let policy = PathSafetyPolicy()
        let trashFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash/some-item.txt", isDirectory: false)
        let flags = policy.riskFlags(for: trashFile, isDirectory: false)
        XCTAssertEqual(flags, [.insideTrash])
        XCTAssertTrue(policy.shouldSkipTraversal(of: trashFile))
    }

    func testVolumeTrashesAreFlagged() {
        let policy = PathSafetyPolicy()
        let flags = policy.riskFlags(for: URL(fileURLWithPath: "/Volumes/Backup/.Trashes/501/old.zip"), isDirectory: false)
        XCTAssertEqual(flags, [.insideTrash])
    }

    // MARK: - Symlinked ancestor escape

    func testSymlinkedAncestorIntoProtectedPathIsRejected() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // link → ~/Library/Keychains (protected, exists on every Mac). The
        // literal path looks safe; only resolution reveals the destination.
        let link = root.appendingPathComponent("evil-link", isDirectory: true)
        let keychains = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: keychains)

        let policy = PathSafetyPolicy()
        let auditor = SafetyAuditor(policy: policy)

        let targetURL = link.appendingPathComponent("some-file", isDirectory: false)
        // Create the target THROUGH the link, then capture real device/inode so
        // the audit's identity check passes and reaches the resolved-path check.
        try Data("x".utf8).write(to: targetURL)
        let record = makeRecord(id: "t1", url: targetURL)
        let action = makeApprovedTrashAction(targets: [record.id])
        do {
            _ = try await auditor.audit(action: action, filesByID: [record.id: record])
            XCTFail("A target under a symlinked protected ancestor must be rejected")
        } catch let error as SafetyAuditError {
            guard case .unsafePath = error else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    // MARK: - Pre-mutation identity verification

    func testVerifyTargetUnchangedRejectsSwappedFile() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileA = root.appendingPathComponent("original.txt")
        try Data("first".utf8).write(to: fileA)

        let record = makeRecord(id: "swap", url: fileA)
        let auditor = SafetyAuditor()

        try await auditor.verifyTargetUnchanged(record)

        // Replace the file with a DIFFERENT inode at the same path (atomic-save pattern).
        let replacement = root.appendingPathComponent("replacement.txt")
        try Data("second".utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(fileA, withItemAt: replacement)

        do {
            try await auditor.verifyTargetUnchanged(record)
            XCTFail("A swapped file must fail pre-mutation verification")
        } catch let error as SafetyAuditError {
            guard case .identityMismatch = error else {
                return XCTFail("Expected identityMismatch, got \(error)")
            }
        }
    }

    func testVerifyTargetUnchangedReportsVanishedTarget() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("gone.txt")
        try Data("x".utf8).write(to: file)
        let record = makeRecord(id: "gone", url: file)
        let auditor = SafetyAuditor()
        try await auditor.verifyTargetUnchanged(record)
        try FileManager.default.removeItem(at: file)
        do {
            try await auditor.verifyTargetUnchanged(record)
            XCTFail("A vanished target must be reported")
        } catch let error as SafetyAuditError {
            guard case .targetVanished = error else {
                return XCTFail("Expected targetVanished, got \(error)")
            }
        }
    }

    // MARK: - Double-execution guard

    func testAlreadyExecutedActionIsRejectedWithoutSideEffects() async throws {
        let store = try makeStore()
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("already-done.txt")
        try Data("keep".utf8).write(to: file)
        let record = makeRecord(id: "dup", url: file)
        var action = makeApprovedTrashAction(targets: [record.id])
        action.executedAt = Date()

        let executor = TestFixtures.makeExecutor(store: store)
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])

        XCTAssertEqual(summary.failedActionIDs, [action.id], "Stamped actions are refused")
        XCTAssertTrue(summary.failures.contains { $0.contains("already executed") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Refused action must not touch the filesystem")
        XCTAssertTrue(summary.logs.isEmpty && summary.undoRecords.isEmpty)
    }

    // MARK: - Write-ahead undo trail

    func testFailedTrashLeavesFailedUndoRecordNotPending() async throws {
        let store = try makeStore()
        let missingRecord = makeRecord(id: "ghost", url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).txt"))
        let action = makeApprovedTrashAction(targets: [missingRecord.id])

        let executor = TestFixtures.makeExecutor(store: store)
        let summary = await executor.execute(actions: [action], filesByID: [missingRecord.id: missingRecord])

        XCTAssertEqual(summary.undoRecords.count, 0, "No successful trash means no finalized undo record in the summary")
        let pending = try await store.loadStalePendingUndos(olderThan: Date())
        XCTAssertTrue(pending.allSatisfy { $0.undo.status != .available }, "Interrupted attempts never surface as undoable")
    }

    // MARK: - MoCleanScanner root dedupe

    func testNestedRootsAreDeduplicatedKeepingOutermost() {
        let base = URL(fileURLWithPath: "/tmp/base")
        let roots = [
            base.appendingPathComponent("Google/Chrome"),
            base.appendingPathComponent("Google/Chrome/GPUCache"),
            base.appendingPathComponent("Firefox")
        ]
        let deduped = MoCleanScanner.deduplicatedRoots(roots)
        XCTAssertEqual(Set(deduped.map(\.lastPathComponent)), ["Chrome", "Firefox"])
    }

    // MARK: - Subtree byte index (O(n log n) replacement for hasPrefix scans)

    func testSubtreeByteIndexSumsDescendantsIntoParents() {
        let root = URL(fileURLWithPath: "/tmp/idx")
        let records = [
            makeRecord(id: "1", url: root),
            makeRecord(id: "2", url: root.appendingPathComponent("Cache")),
            makeRecord(id: "3", url: root.appendingPathComponent("Cache/deep")),
            makeRecord(id: "4", url: root.appendingPathComponent("Cache/deep/a.bin")),
            makeRecord(id: "5", url: root.appendingPathComponent("other.txt")),
        ]
        var sized = records
        sized[0].sizeBytes = 0          // directories report 0 own size
        sized[1].sizeBytes = 0
        sized[2].sizeBytes = 0
        sized[3].sizeBytes = 700        // Cache/deep/a.bin
        sized[4].sizeBytes = 90         // other.txt

        let index = MoCleanScanner.buildSubtreeByteIndex(files: sized)
        XCTAssertEqual(index["/tmp/idx/Cache/deep/a.bin"], 700)
        XCTAssertEqual(index["/tmp/idx/Cache/deep"], 700)
        XCTAssertEqual(index["/tmp/idx/Cache"], 700)
        XCTAssertEqual(index["/tmp/idx"], 790)
    }

    // MARK: - PlannerAgent risk clamp

    func testAIRiskCannotFallBelowRiskFlagFloor() async {
        // secretOrCertificate → floor .high; AI claims low ⇒ clamped to high.
        var record = makeRecord(id: "secret", url: URL(fileURLWithPath: "/Users/me/project/server.pem"))
        record.riskFlags = [.secretOrCertificate]
        let planner = PlannerAgent()
        let recommendation = Recommendation(
            id: "r1", findingID: "f1", actionType: .inspectOnly, targetFileIDs: ["secret"],
            confidence: 0.9, risk: .low, reason: "test", expectedBytesReclaimed: 0,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: "test"
        )
        let payload = AIRecommendationPayload(
            category: .browserCache, action: .moveToTrash, targetFileID: "secret",
            confidence: 0.9, risk: .low, reason: "looks safe to me"
        )
        let plan = await planner.makePlan(sessionID: "s1", recommendations: [recommendation], filesByID: ["secret": record], aiRecommendations: [payload])
        let aiAction = plan.actions.first { $0.targets == ["secret"] && $0.findingID == nil }
        XCTAssertEqual(aiAction?.risk, .high, "AI-declared risk may not undercut the flag-derived floor")
    }

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SafetyHardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStore() throws -> SQLiteStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("safety-\(UUID().uuidString).sqlite")
        return try SQLiteStore(databaseURL: url)
    }

    private func makeRecord(id: String, url: URL) -> FileRecord {
        FileRecord(
            id: id, scanSessionID: "session", source: .local, url: url,
            displayPath: url.path, fileName: url.lastPathComponent,
            fileExtension: url.pathExtension, utiDescription: nil,
            kind: .regularFile, sizeBytes: 1024,
            createdAt: Date(), modifiedAt: Date(), lastOpenedAt: nil,
            owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
            isPackage: false, isCloudPlaceholder: false, cloudProvider: nil,
            finderTags: [], spotlightMetadata: [:], riskFlags: [],
            identity: FileArtifactIdentity.capture(at: url).map {
                FileIdentity(deviceIdentifier: $0.deviceID, inodeIdentifier: $0.inodeID, resourceIdentifier: nil)
            } ?? FileIdentity(deviceIdentifier: 1, inodeIdentifier: 1, resourceIdentifier: nil),
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
            reason: "regression fixture",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )
    }
}
