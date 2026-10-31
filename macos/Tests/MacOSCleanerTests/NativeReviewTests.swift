import Foundation
import XCTest

@testable import MacOSCleanerAppKit
@testable import MacOSCleanerCore

@MainActor
final class NativeReviewTests: XCTestCase {
    private func makeModel(_ actions: [PlannedAction]) throws -> AppViewModel {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let defaults = makeIsolatedDefaults()
        let model = AppViewModel(
            store: store, keychain: KeychainStore(inMemory: true), memory: memory,
            orchestrator: ScanOrchestrator(store: store, memory: memory),
            executor: TestFixtures.makeExecutor(store: store), undoService: UndoManagerService(store: store, memory: memory),
            reportGenerator: ReportGenerator(store: store), notifications: NotificationScheduler(),
            planner: PlannerAgent(), defaults: defaults
        )
        model.plan = Plan(
            id: "plan", scanSessionID: "scan", createdAt: Date(), status: .proposed,
            summary: "Test plan", estimatedReclaimableBytes: 0, estimatedFilesAffected: 0,
            riskBreakdown: [:], actions: actions
        )
        return model
    }

    private func action(
        _ id: String, risk: RiskLevel = .low, type: ActionType = .moveToTrash,
        decision: UserDecision = .approved, targets: [String] = ["file"]
    ) -> PlannedAction {
        PlannedAction(
            id: id, planID: "plan", actionType: type, targets: targets, status: .approved,
            risk: risk, confidence: 0.99, reason: id, userDecision: decision
        )
    }

    func testConfirmationCountsUniqueTargetsAndExcludesUnavailableActions() throws {
        var completed = action("completed")
        completed.executedAt = Date()
        completed.status = .completed
        let model = try makeModel([
            action("one", targets: ["a", "b"]), action("two", targets: ["b", "c"]),
            action("blocked", risk: .forbidden), action("inspection", type: .inspectOnly),
            action("undecided", decision: .undecided), completed
        ])
        let request = try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .high))
        XCTAssertEqual(request.actionIDs, ["one", "two"])
        XCTAssertEqual(request.fileCount, 0)
        XCTAssertEqual(request.unresolvedTargetCount, 3)
        XCTAssertTrue(request.isTrashOnly)
    }

    func testLowRiskConfirmationKeepsOtherApprovedActionsPending() throws {
        let model = try makeModel([action("low"), action("medium", risk: .medium), action("high", risk: .high)])
        let request = try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .low))
        XCTAssertEqual(request.actionIDs, ["low"])
        XCTAssertEqual(model.pendingExecutableActions().count, 3)
    }

    func testChangedDestinationOrApprovalInvalidatesConfirmation() throws {
        let model = try makeModel([action("one")])
        let request = try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .high))
        XCTAssertTrue(request.isCurrent(in: model))
        model.plan?.actions[0].destination = URL(fileURLWithPath: "/tmp/changed")
        XCTAssertFalse(request.isCurrent(in: model))
        let refreshed = try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .high))
        model.reject(try XCTUnwrap(model.plan?.actions.first))
        XCTAssertFalse(refreshed.isCurrent(in: model))
    }

    func testStaleConfirmationDoesNotExecute() async throws {
        let model = try makeModel([action("one")])
        let request = try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .high))
        model.plan?.summary = "Changed"
        await model.executeConfirmedRequest(request)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isExecuting)
        XCTAssertNil(model.executionSummary)
    }

    func testSelectingActionDoesNotApproveIt() throws {
        let model = try makeModel([action("one", decision: .undecided)])
        model.destination = .largeFiles
        model.selectedActionID = "one"
        model.showsInspector = true
        XCTAssertEqual(model.selectedAction?.userDecision, .undecided)
        XCTAssertTrue(model.pendingExecutableActions().isEmpty)
        XCTAssertNil(ExecutionRequest(model: model, maximumRisk: .high))
    }

    func testMixedOperationConfirmationDoesNotUseTrashLabel() throws {
        let model = try makeModel([action("trash"), action("tag", type: .tag)])
        let request = try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .high))
        XCTAssertFalse(request.isTrashOnly)
        XCTAssertEqual(request.operationTypes.count, 2)
    }

    func testReviewSearchMatchesReasonWithoutChangingApproval() throws {
        let model = try makeModel([action("Old installer", decision: .undecided), action("Cache")])
        model.searchText = "INSTALLER"
        let visible = (model.plan?.actions ?? []).filter(model.actionMatchesSearch)
        XCTAssertEqual(visible.map(\.id), ["Old installer"])
        XCTAssertEqual(visible.first?.userDecision, .undecided)
    }

    func testNewInstallationUsesListView() throws {
        let model = try makeModel([])
        XCTAssertEqual(model.exploreViewKindRaw, "list")
        XCTAssertEqual(model.destination, .overview)
    }
    func testTrashEstimateIncludesMeasuredFoldersWithoutCountingChildrenTwice() {
        var directory = TestFixtures.makeFileRecord(id: "folder", path: "/Users/test/App Data", sizeBytes: 800)
        directory.kind = .directory
        let child = TestFixtures.makeFileRecord(id: "child", path: "/Users/test/App Data/cache", sizeBytes: 300)
        let other = TestFixtures.makeFileRecord(id: "other", path: "/Users/test/Other", sizeBytes: 100)
        let actions = [action("all", targets: ["folder", "child", "other"]), action("overlap", targets: ["child"])]
        XCTAssertEqual(ExecutionRequest.estimatedTrashBytes(actions: actions, files: [directory, child, other]), 900)
        directory.sizeBytes = 0
        XCTAssertEqual(ExecutionRequest.estimatedTrashBytes(actions: actions, files: [directory, child, other]), 400)
    }

    func testTrashEstimateRetainsSelectedPathWhenAnotherRecordHasLargerSize() {
        let selected = TestFixtures.makeFileRecord(id: "selected", path: "/Users/test/cache", sizeBytes: 100)
        let duplicate = TestFixtures.makeFileRecord(id: "duplicate", path: "/Users/test/cache", sizeBytes: 200)
        XCTAssertEqual(
            ExecutionRequest.estimatedTrashBytes(
                actions: [action("trash", targets: ["selected"])], files: [selected, duplicate]), 200)
    }

    func testCancelledPlanningDoesNotChangePlanOrSelection() async throws {
        let model = try makeModel([action("low"), action("high", risk: .high)])
        model.naturalLanguageCommand = "safe"
        model.selectedActionID = "high"
        let originalSignature = model.executionPlanSignature
        let task = Task { await model.applyNaturalLanguageCommand() }
        task.cancel()
        _ = await task.value
        XCTAssertEqual(model.executionPlanSignature, originalSignature)
        XCTAssertEqual(model.selectedActionID, "high")
        XCTAssertFalse(model.isPlanning)
    }

    func testReviewKeyboardSelectionExcludesRowsHiddenByRiskOrSearch() throws {
        let model = try makeModel([action("Cache"), action("Installer", risk: .high, decision: .undecided)])
        model.destination = .largeFiles
        model.selectedActionID = "Installer"
        XCTAssertEqual(model.selectedVisibleReviewAction?.id, "Installer")
        model.reviewRiskFilter = .low
        XCTAssertNil(model.selectedVisibleReviewAction)
        XCTAssertEqual(model.visibleReviewActions.map(\.id), ["Cache"])
        model.reviewRiskFilter = nil
        model.searchText = "cache"
        XCTAssertNil(model.selectedVisibleReviewAction)
        XCTAssertEqual(model.selectedAction?.userDecision, .undecided)
        model.searchText = "installer"
        XCTAssertEqual(model.selectedVisibleReviewAction?.id, "Installer")
    }

    func testSuccessfulPlanningIsIndependentOfAnUnrelatedVisibleError() async throws {
        let model = try makeModel([action("Cache"), action("Installer", risk: .high)])
        model.errorMessage = "A previous report could not be saved."
        model.naturalLanguageCommand = "safe"
        let applied = await model.applyNaturalLanguageCommand()
        XCTAssertTrue(applied)
        XCTAssertEqual(model.plan?.actions.map(\.id), ["Cache"])
        XCTAssertNotNil(model.errorMessage, "Unresolved errors stay visible until dismissed.")
    }

    func testReviewLinkRevealsItsActionWithoutApprovingIt() throws {
        let model = try makeModel([action("Duplicate", risk: .medium, decision: .undecided)])
        model.destination = .duplicates
        model.reviewRiskFilter = .high
        model.searchText = "unrelated"
        model.showReviewAction(id: "Duplicate")
        XCTAssertEqual(model.destination, .largeFiles)
        XCTAssertEqual(model.selectedVisibleReviewAction?.id, "Duplicate")
        XCTAssertEqual(model.selectedAction?.userDecision, .undecided)
        XCTAssertTrue(model.showsInspector)
    }

    func testEveryCategoryHasOneReviewRow() {
        for category in FindingCategory.allCases {
            let row = AppDestination.forCategory(category)
            XCTAssertTrue(row.isReview || row == .duplicates, "\(category) routes to \(row)")
        }
        XCTAssertEqual(AppDestination.forCategory(nil), .largeFiles)
    }

    func testRowsShowOnlyTheirOwnActionsSoBulkCommandsStayInScope() throws {
        var cache = action("cache", decision: .undecided)
        cache.findingID = "f-cache"
        var build = action("build", decision: .undecided)
        build.findingID = "f-build"
        let model = try makeModel([cache, build])
        model.outcome = outcome(findings: [finding("f-cache", .cache), finding("f-build", .developerArtifact)])
        XCTAssertEqual(model.actions(in: .systemJunk).map(\.id), ["cache"])
        XCTAssertEqual(model.actions(in: .developer).map(\.id), ["build"])
        model.destination = .systemJunk
        XCTAssertEqual(model.visibleReviewActions.map(\.id), ["cache"])
        model.selectedActionID = "build"
        XCTAssertNil(model.selectedVisibleReviewAction, "A row from another area must not receive menu commands")
    }

    private func finding(_ id: String, _ category: FindingCategory) -> Finding {
        Finding(
            id: id, scanSessionID: "scan", category: category, severity: .low, confidence: 0.9,
            bytesReclaimable: 0, summary: id, evidence: [:], targetFileIDs: ["file"])
    }

    private func outcome(findings: [Finding]) -> ScanOutcome {
        ScanOutcome(
            session: ScanSession(scanType: .homeFolder, rootURLs: [], permissionsSnapshot: "test"),
            files: [], fingerprints: [], contentSummaries: [], projects: [], edges: [], findings: findings,
            recommendations: [],
            snapshot: StorageSnapshot(
                id: "snapshot", createdAt: Date(), totalBytes: 0, bytesByCategory: [:], bytesByRootPath: [:],
                bytesByProject: [:], removedBytesThroughApp: 0),
            packageCandidates: [])
    }
}
