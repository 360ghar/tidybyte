import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Regression tests for Wave 2D planner and safety-auditor correctness:
/// 1. "duplicates" natural-language commands match the grouped duplicate action.
/// 2. "organize" commands produce `.move` actions with a concrete destination
///    inside the scanned root.
/// 3. Actions that used to audit to `.needsManualReview` are no longer emitted
///    as execute-able dead-ends (approval is the review for provider cleanups).
/// 4. High-risk destructive actions require the explicit confirmation flag.
final class PlannerSafetyTests: XCTestCase {

    // MARK: - Bug 1: "duplicates" NL filter

    func testDuplicatesNLCommandMatchesGroupedDuplicateAction() async {
        // Real-pipeline shape: the duplicate detector emits ONE action whose targets
        // are all duplicate copies, so counting target occurrences across actions
        // finds nothing. The action must be matched by its reason instead.
        let dupA = makeFile(id: "dup-a", path: "/tmp/Downloads/photo-a.jpg", bytes: 1024)
        let dupB = makeFile(id: "dup-b", path: "/tmp/Downloads/photo-b.jpg", bytes: 1024)
        let cache = makeFile(id: "cache", path: "/tmp/Caches/App/cache.bin", bytes: 2048)
        let screenshotA = makeFile(id: "shot-a", path: "/tmp/Desktop/Shot 2024-01-01.png", bytes: 4096)
        let screenshotB = makeFile(id: "shot-b", path: "/tmp/Desktop/Shot 2024-01-02.png", bytes: 4096)
        let filesByID = [dupA.id: dupA, dupB.id: dupB, cache.id: cache, screenshotA.id: screenshotA, screenshotB.id: screenshotB]

        let duplicateAction = makeAction(
            id: "duplicate-action",
            actionType: .moveToTrash,
            targets: [dupA.id, dupB.id],
            reason: "These files have the same size, quick hash, and full content hash. Keep the newest copy and move duplicate copies to Trash."
        )
        let cacheAction = makeAction(
            id: "cache-action",
            actionType: .moveToTrash,
            targets: [cache.id],
            reason: "Caches and logs are usually rebuildable."
        )
        // A grouped multi-target action that is NOT about duplicates (screenshot
        // rule groups by folder) must not be surfaced by a duplicates command.
        let screenshotAction = makeAction(
            id: "screenshot-action",
            actionType: .moveToTrash,
            targets: [screenshotA.id, screenshotB.id],
            reason: "Review screenshots and screen recordings before moving them to Trash."
        )
        let plan = makePlan(actions: [duplicateAction, cacheAction, screenshotAction])

        let planner = PlannerAgent()
        for command in ["duplicates", "duplicate files", "clean duplicates"] {
            let filtered = await planner.planForNaturalLanguageCommand(command, existingPlan: plan, filesByID: filesByID)
            XCTAssertEqual(filtered.actions.map(\.id), ["duplicate-action"], "command: \(command)")
        }
    }

    func testDuplicatesNLCommandThroughRealPipeline() async throws {
        let root = try makeTemporaryDirectory(named: "PlannerDupes")
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("identical payload".utf8)
        try payload.write(to: root.appendingPathComponent("copy-a.txt", isDirectory: false))
        try payload.write(to: root.appendingPathComponent("copy-b.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let filesByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(files: records, sessionID: "scan")
        XCTAssertFalse(analysis.recommendations.isEmpty, "Fixture should produce duplicate recommendations")

        let planner = PlannerAgent()
        let plan = await planner.makePlan(sessionID: "scan", recommendations: analysis.recommendations, filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("clean duplicates", existingPlan: plan, filesByID: filesByID)
        XCTAssertFalse(filtered.actions.isEmpty, "Duplicates command should surface the duplicate action")
        let targetIDs = Set(filtered.actions.flatMap(\.targets))
        XCTAssertTrue(targetIDs.isSubset(of: Set(records.map(\.id))))
    }

    // MARK: - Bug 2: organize commands produce a concrete move destination

    func testOrganizeNLCommandProducesMoveWithConcreteDestination() async throws {
        let target = makeFile(id: "f1", path: "/Users/me/Downloads/sub/old-report.pdf", bytes: 500)
        let filesByID = [target.id: target]
        let rec = Recommendation(
            id: "r1", findingID: "finding-1", actionType: .tag, targetFileIDs: [target.id],
            confidence: 0.8, risk: .low, reason: "Old downloads benefit from organization.",
            expectedBytesReclaimed: 0, requiresConfirmation: false, llmTraceID: nil, policyTraceID: nil
        )
        let planner = PlannerAgent()
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("organize files", existingPlan: plan, filesByID: filesByID)
        let action = try XCTUnwrap(filtered.actions.first)
        XCTAssertEqual(action.actionType, .move)
        let destination = try XCTUnwrap(action.destination, "Organize move must have a concrete destination")
        XCTAssertEqual(destination.lastPathComponent, "Organized")
        // Destination must be inside the scanned root (a descendant of the target's parent).
        XCTAssertTrue(destination.path.hasPrefix(target.url.deletingLastPathComponent().path + "/"))
    }

    func testOrganizeDestinationFallsBackToFirstTargetParentWhenRootsDiverge() async throws {
        // Targets in different roots share only "/", which must never be used as the
        // base for an "Organized" folder. Fall back to the first target's parent.
        let a = makeFile(id: "a", path: "/Users/me/Downloads/a.txt", bytes: 100)
        let b = makeFile(id: "b", path: "/Volumes/Other/b.txt", bytes: 100)
        let filesByID = [a.id: a, b.id: b]
        let rec = Recommendation(
            id: "r1", findingID: "finding-1", actionType: .tag, targetFileIDs: [a.id, b.id],
            confidence: 0.8, risk: .low, reason: "Organization.",
            expectedBytesReclaimed: 0, requiresConfirmation: false, llmTraceID: nil, policyTraceID: nil
        )
        let planner = PlannerAgent()
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("sort my downloads", existingPlan: plan, filesByID: filesByID)
        let action = try XCTUnwrap(filtered.actions.first)
        let destination = try XCTUnwrap(action.destination)
        XCTAssertEqual(destination.path, "/Users/me/Downloads/Organized")
        XCTAssertNotEqual(destination.path, "/Organized")
    }

    // MARK: - Bug 3: needsManualReview is not an execute-able dead-end

    func testHighRiskPackageCleanupApprovalIsTheReviewAndNotADeadEnd() async throws {
        let candidate = PackageCleanupCandidate(
            id: "brew-cleanup", title: "brew cleanup",
            commandPath: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [], dryRunOutput: "", risk: .high, category: .packageManagerCleanup
        )
        let rec = Recommendation(
            id: "r1", findingID: "finding-1", actionType: .runPackageManagerCleanup,
            targetFileIDs: [candidate.id], confidence: 0.82, risk: .high,
            reason: "Use the package manager's own cleanup command after reviewing its dry-run output. This is not fully undoable.",
            expectedBytesReclaimed: 0, requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let planner = PlannerAgent()
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec], filesByID: [:])
        let action = try XCTUnwrap(plan.actions.first)

        // Plan keeps the action undecided for the user (reviewable), never pre-failed.
        XCTAssertEqual(action.userDecision, .undecided)
        XCTAssertEqual(action.status, .proposed)

        // Once approved, the audit must not dead-end into .needsManualReview.
        var approved = action
        approved.userDecision = .approved
        approved.status = .approved
        let auditor = SafetyAuditor()
        let audit = try await auditor.audit(action: approved, filesByID: [:])
        XCTAssertEqual(audit.decision, .allowed, "Approval is the required review for provider cleanups")

        // Execution must not mark the action failed.
        let store = try SQLiteStore.inMemory()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)
        let summary = await executor.execute(actions: [approved], filesByID: [:], packageCandidates: [candidate])
        XCTAssertFalse(summary.failedActionIDs.contains(action.id))
        XCTAssertEqual(summary.logs.count, 1)
    }

    // MARK: - Bug 4: explicit confirmation flag for high-risk destructive actions

    func testSafetyAuditorRejectsHighRiskDestructiveWithoutExplicitConfirmation() async throws {
        let (record, filesByID, root) = try await makeRealFileFixture(name: "risky.bin")
        defer { try? FileManager.default.removeItem(at: root) }
        let action = makePlannedAction(
            id: "high-1", actionType: .moveToTrash, targets: [record.id],
            risk: .high, userDecision: .approved
        )
        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: filesByID)
            XCTFail("High-risk destructive action without explicit confirmation must be rejected")
        } catch let error as SafetyAuditError {
            guard case .highRiskDestructiveAction = error else {
                XCTFail("Expected highRiskDestructiveAction, got: \(error)")
                return
            }
        }
    }

    func testSafetyAuditorAllowsHighRiskDestructiveWithExplicitConfirmation() async throws {
        let (record, filesByID, root) = try await makeRealFileFixture(name: "risky.bin")
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Moved", isDirectory: true)
        var action = makePlannedAction(
            id: "high-2", actionType: .move, targets: [record.id],
            risk: .high, userDecision: .approved
        )
        action.destination = destination
        action.requiresExplicitConfirmation = true

        let auditor = SafetyAuditor()
        let audit = try await auditor.audit(action: action, filesByID: filesByID)
        XCTAssertEqual(audit.decision, .allowed)

        let store = try SQLiteStore.inMemory()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)
        let summary = await executor.execute(actions: [action], filesByID: filesByID)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(summary.undoRecords.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("risky.bin").path))
    }

    func testSafetyAuditorKeepsForbiddenPathsRejectedEvenWithExplicitConfirmation() async throws {
        let root = try makeTemporaryDirectory(named: "PlannerForbidden")
        defer { try? FileManager.default.removeItem(at: root) }
        let envURL = root.appendingPathComponent(".env", isDirectory: false)
        try Data("TOKEN=secret".utf8).write(to: envURL)
        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == envURL.standardizedFileURL })
        var action = makePlannedAction(
            id: "protected-1", actionType: .moveToTrash, targets: [record.id],
            risk: .high, userDecision: .approved
        )
        action.requiresExplicitConfirmation = true

        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: [record.id: record])
            XCTFail("Protected path must be rejected even with explicit confirmation")
        } catch let error as SafetyAuditError {
            guard case .unsafePath = error else {
                XCTFail("Expected unsafePath, got: \(error)")
                return
            }
        }
    }

    // MARK: - Fixtures

    private func makeTemporaryDirectory(named prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleaner-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRealFileFixture(name: String) async throws -> (record: FileRecord, filesByID: [String: FileRecord], root: URL) {
        let root = try makeTemporaryDirectory(named: "PlannerSafety")
        let url = root.appendingPathComponent(name, isDirectory: false)
        try Data("fixture content".utf8).write(to: url)
        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        guard let record = records.first(where: { $0.url == url.standardizedFileURL }) else {
            throw FixtureError.missingRecord
        }
        return (record, [record.id: record], root)
    }

    private func makePlan(actions: [PlannedAction]) -> Plan {
        Plan(
            id: "plan",
            scanSessionID: "scan",
            createdAt: Date(),
            status: .proposed,
            summary: "fixture plan",
            estimatedReclaimableBytes: 0,
            estimatedFilesAffected: Set(actions.flatMap(\.targets)).count,
            riskBreakdown: Dictionary(grouping: actions, by: \.risk).mapValues(\.count),
            actions: actions
        )
    }

    private func makeAction(id: String, actionType: ActionType, targets: [String], reason: String) -> PlannedAction {
        PlannedAction(
            id: id,
            planID: "plan",
            actionType: actionType,
            targets: targets,
            destination: nil,
            status: .proposed,
            risk: .low,
            confidence: 0.9,
            reason: reason,
            userDecision: .undecided,
            executedAt: nil,
            findingID: id
        )
    }

    private func makePlannedAction(id: String, actionType: ActionType, targets: [String], risk: RiskLevel, userDecision: UserDecision) -> PlannedAction {
        PlannedAction(
            id: id,
            planID: "plan",
            actionType: actionType,
            targets: targets,
            destination: nil,
            status: .proposed,
            risk: risk,
            confidence: 0.9,
            reason: "fixture action",
            userDecision: userDecision,
            executedAt: nil,
            findingID: nil
        )
    }

    private func makeFile(id: String, path: String, bytes: Int64) -> FileRecord {
        let url = URL(fileURLWithPath: path)
        return FileRecord(
            id: id,
            scanSessionID: "scan",
            source: .local,
            url: url,
            displayPath: url.path,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            utiDescription: nil,
            kind: .regularFile,
            sizeBytes: bytes,
            createdAt: nil,
            modifiedAt: nil,
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
            identity: FileIdentity(deviceIdentifier: nil, inodeIdentifier: nil, resourceIdentifier: nil),
            capabilities: [.canMove, .canTrash, .canRestore]
        )
    }
}

private enum FixtureError: Error {
    case missingRecord
}
