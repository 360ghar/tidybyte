import Foundation
@testable import MacOSCleanerAppKit
@testable import MacOSCleanerCore
import XCTest

/// Unit tests for `AppViewModel` (the @MainActor @Observable app shell).
///
/// Safety rules for this suite:
/// - All scans run against tiny temp directories (selectedFolders mode); never real home folders.
/// - Execution tests only run `.tag` actions on temp files (xattr writes, no Trash) or actions
///   that fail fast (`.inspectOnly`); never `moveToTrash` against real files.
/// - Every model is built with an isolated `UserDefaults` suite; the user's real defaults are
///   never read or written. The `defaults` injection point is the only AppViewModel change
///   that was allowed for this suite.
@MainActor
final class AppViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeTemporaryDirectory(named prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleaner-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaultsSuite() -> UserDefaults {
        makeIsolatedDefaults()
    }

    /// Reads Finder tags for a file, mapping the "no tags" case (nil) to an empty
    /// array — URLResourceValues.tagNames is nil for untagged files, not [].
    private func readFinderTags(at url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    private func makeModel(defaults: UserDefaults, store: SQLiteStore? = nil, inboxRoot: URL? = nil) throws -> AppViewModel {
        let resolvedStore = try store ?? SQLiteStore.inMemory()
        let memory = MemoryEngine(store: resolvedStore)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: resolvedStore, memory: memory)
        let executor = TestFixtures.makeExecutor(store: resolvedStore)
        let undo = UndoManagerService(store: resolvedStore, memory: memory)
        let reports = ReportGenerator(store: resolvedStore)
        return AppViewModel(
            store: resolvedStore,
            keychain: KeychainStore(inMemory: true),
            memory: memory,
            orchestrator: orchestrator,
            executor: executor,
            undoService: undo,
            reportGenerator: reports,
            notifications: NotificationScheduler(),
            planner: planner,
            defaults: defaults,
            inboxRoot: inboxRoot
        )
    }

    private func makeModelWithStore(defaults: UserDefaults) throws -> (model: AppViewModel, store: SQLiteStore) {
        let store = try SQLiteStore.inMemory()
        let model = try makeModel(defaults: defaults, store: store)
        return (model, store)
    }

    /// Tiny temp scan root with files that produce a mix of low-risk (cache), medium-risk
    /// (organization tag), and other cleanup actions (developer artifact, old installer,
    /// duplicate) through the real rule engine pipeline.
    private func makeScanFixtureRoot() throws -> URL {
        let root = try makeTemporaryDirectory(named: "AppVMScan")
        _ = try UserStoryFixtures.writeFile("Caches/App/cache.bin", in: root, data: Data(repeating: 1, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile("Project/package.json", in: root, data: Data("{}".utf8))
        _ = try UserStoryFixtures.writeFile("Project/node_modules/package.bin", in: root, data: Data(repeating: 2, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile("Downloads/notes.pdf", in: root, data: Data("%PDF-1.4".utf8), modifiedDaysAgo: 14)
        _ = try UserStoryFixtures.writeFile("Downloads/old-installer.dmg", in: root, data: Data("installer".utf8), modifiedDaysAgo: 45)
        _ = try UserStoryFixtures.writeFile("Downloads/duplicate-a.txt", in: root, data: Data("same-payload".utf8))
        _ = try UserStoryFixtures.writeFile("Downloads/duplicate-b.txt", in: root, data: Data("same-payload".utf8))
        return root
    }

    /// Polls until `condition` returns true or the timeout elapses. Runs on the main actor,
    /// so the scan/execution tasks can make progress between polls.
    private func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// Starts `runScan()` and waits until it either produces a plan or sets an error,
    /// then waits for `isScanning` to clear so post-scan assertions are race-free.
    @discardableResult
    private func runScanToCompletion(_ model: AppViewModel, timeout: TimeInterval = 20) async -> Bool {
        model.runScan()
        let settled = await waitUntil(timeout: timeout) {
            model.plan != nil || model.errorMessage != nil
        }
        if settled {
            _ = await waitUntil(timeout: timeout) { !model.isScanning }
        }
        return settled
    }

    private func runScanOnFixture(_ model: AppViewModel, root: URL) async -> Bool {
        model.selectedMode = .selectedFolders
        model.selectedFolders = [root]
        return await runScanToCompletion(model)
    }

    // MARK: - 1. Initial state

    func testInitialStateShowsOnboardingAndIdleFlags() throws {
        // Given a fresh model with an isolated (empty) defaults suite
        let model = try makeModel(defaults: makeDefaultsSuite())

        // Then the app starts in onboarding with idle scan/execution state (ON-01)
        XCTAssertTrue(model.showOnboarding)
        XCTAssertEqual(model.statusMessage, "Choose folders or a scan mode to begin.")
        XCTAssertFalse(model.isScanning)
        XCTAssertFalse(model.isExecuting)
        XCTAssertNil(model.plan)
        XCTAssertNil(model.outcome)
        XCTAssertTrue(model.undoRecords.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.selectedMode, .selectedFolders)
        XCTAssertEqual(model.selectedFolders, [])
        XCTAssertEqual(model.cleanupPosture, .conservative)
    }

    // MARK: - 2. Settings persistence

    func testSettingsRoundTripPersistsAcrossModels() throws {
        // Given a model with an injected isolated defaults suite and persisted values
        let suite = makeDefaultsSuite()
        let root = try makeTemporaryDirectory(named: "SettingsRoot")
        let first = try makeModel(defaults: suite)
        first.selectedMode = .homeFolder
        first.selectedFolders = [root]
        first.cleanupPosture = .aggressive
        first.includeAI = true
        first.providerSettings.providerName = "Test Provider"
        first.providerSettings.apiBaseURL = URL(string: "https://example.test/v1")!
        first.providerSettings.textModel = "test-model"
        first.providerSettings.maxTokens = 2048
        first.providerSettings.temperature = 0.7
        first.providerSettings.privacyMode = .snippetsAI
        first.saveSettings()

        // When a second model is created against the same suite
        let second = try makeModel(defaults: suite)

        // Then every persisted setting is restored (ST-02, ST-03, ST-04..08, ST-09, ST-10, ON-09, ON-10)
        XCTAssertEqual(second.selectedMode, .homeFolder)
        XCTAssertEqual(second.selectedFolders.map(\.path), [root.path])
        XCTAssertEqual(second.cleanupPosture, .aggressive)
        XCTAssertTrue(second.includeAI)
        XCTAssertEqual(second.providerSettings.providerName, "Test Provider")
        XCTAssertEqual(second.providerSettings.apiBaseURL, URL(string: "https://example.test/v1"))
        XCTAssertEqual(second.providerSettings.textModel, "test-model")
        XCTAssertEqual(second.providerSettings.maxTokens, 2048)
        XCTAssertEqual(second.providerSettings.temperature, 0.7)
        XCTAssertEqual(second.providerSettings.privacyMode, .snippetsAI)
        XCTAssertFalse(second.showOnboarding, "Persisted folders must dismiss onboarding on relaunch.")
    }

    func testSettingsAreIsolatedFromOtherDefaultsSuites() throws {
        // Given two models backed by two different isolated suites
        let suiteA = makeDefaultsSuite()
        let suiteB = makeDefaultsSuite()
        let first = try makeModel(defaults: suiteA)
        first.selectedMode = .developerCleanup
        first.saveSettings()

        // When a model is created against a different suite
        let second = try makeModel(defaults: suiteB)

        // Then it must not see the other suite's saved values
        XCTAssertEqual(second.selectedMode, .selectedFolders, "A different defaults suite must not leak settings.")

        // And the original suite still restores its own value
        let refreshed = try makeModel(defaults: suiteA)
        XCTAssertEqual(refreshed.selectedMode, .developerCleanup)
    }

    // MARK: - 3. Folder management

    func testAddScanFolderUpdatesSelectionAndMode() throws {
        // Given a fresh model and an existing temp folder
        let model = try makeModel(defaults: makeDefaultsSuite())
        let root = try makeTemporaryDirectory(named: "FolderMgmt")

        // When the user adds the folder (ON-05)
        model.addScanFolder(root)

        // Then it is selected, the mode switches to selected folders, and onboarding dismisses
        XCTAssertEqual(model.selectedFolders.map(\.path), [root.standardizedFileURL.path])
        XCTAssertEqual(model.selectedMode, .selectedFolders)
        XCTAssertFalse(model.showOnboarding)
        XCTAssertTrue(model.statusMessage.contains("1 folder selected"))

        // Adding the same folder again is a no-op (dedupe)
        model.addScanFolder(root)
        XCTAssertEqual(model.selectedFolders.count, 1)

        // Adding a second folder keeps both
        let secondRoot = try makeTemporaryDirectory(named: "FolderMgmt2")
        model.addScanFolder(secondRoot)
        XCTAssertEqual(model.selectedFolders.count, 2)
    }

    func testAddScanFolderRejectsMissingFolder() throws {
        // Given a model and a temp root that does not exist
        let model = try makeModel(defaults: makeDefaultsSuite())
        let root = try makeTemporaryDirectory(named: "FolderMgmtMissing")

        // When the user adds the missing folder
        model.addScanFolder(root.appendingPathComponent("does-not-exist"))

        // Then an error is surfaced and nothing is selected
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.selectedFolders.isEmpty)
    }

    func testRemoveAndClearSelectedFoldersResetState() throws {
        // Given a model with one selected folder
        let model = try makeModel(defaults: makeDefaultsSuite())
        let root = try makeTemporaryDirectory(named: "FolderMgmtRemove")
        model.addScanFolder(root)

        // When the user removes the last folder
        model.removeSelectedFolder(root)

        // Then selection is empty and onboarding returns in folder mode
        XCTAssertTrue(model.selectedFolders.isEmpty)
        XCTAssertTrue(model.showOnboarding)
        XCTAssertTrue(model.statusMessage.contains("No folders selected"))

        // Clearing an empty list is a no-op status message
        model.clearSelectedFolders()
        XCTAssertTrue(model.statusMessage.contains("No folders selected"))

        // Clearing a populated list empties it and returns to onboarding
        model.addScanFolder(root)
        model.clearSelectedFolders()
        XCTAssertTrue(model.selectedFolders.isEmpty)
        XCTAssertTrue(model.showOnboarding)
        XCTAssertTrue(model.statusMessage.contains("All scan folders removed"))
    }

    func testCreateInboxUsesInjectableInboxRoot() async throws {
        // ON-03 (inbox story): createInbox() must create the inbox under the injected
        // root so tests never touch the real home directory.
        let defaults = makeDefaultsSuite()
        let inboxRoot = try makeTemporaryDirectory(named: "InboxRoot")
        let model = try makeModel(defaults: defaults, inboxRoot: inboxRoot)
        model.selectedMode = .homeFolder
        XCTAssertTrue(model.showOnboarding)

        // When the user creates the inbox
        await model.createInbox()

        // Then the inbox directory exists under the temp root, is added to the
        // selection, and onboarding dismisses
        XCTAssertTrue(FileManager.default.fileExists(atPath: inboxRoot.path))
        XCTAssertTrue(model.selectedFolders.contains(inboxRoot))
        XCTAssertEqual(model.selectedMode, .selectedFolders)
        XCTAssertFalse(model.showOnboarding)
        XCTAssertTrue(model.statusMessage.contains("Tidybyte Inbox is ready"))
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - 4. Scan lifecycle

    func testScanLifecycleCompletesAndPopulatesWorkspace() async throws {
        // Given a model pointed at a temp scan root with enough files that the scan
        // is observably in flight while it runs (SP-30)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeTemporaryDirectory(named: "AppVMScanHeavy")
        for index in 0..<8 {
            _ = try UserStoryFixtures.writeFile(
                "Caches/App/cache-\(index).bin",
                in: root,
                data: Data(repeating: UInt8(index), count: 4_000_000)
            )
        }
        _ = try UserStoryFixtures.writeFile("Downloads/notes.pdf", in: root, data: Data("%PDF-1.4".utf8), modifiedDaysAgo: 14)

        // When the scan runs
        model.selectedMode = .selectedFolders
        model.selectedFolders = [root]
        model.runScan()

        // Then isScanning becomes true while the scan is in flight (SP-30)
        var sawScanning = false
        let settled = await waitUntil(timeout: 20) {
            if model.isScanning { sawScanning = true }
            return model.plan != nil || model.errorMessage != nil
        }
        XCTAssertTrue(settled, "Scan should complete within the timeout.")
        XCTAssertTrue(sawScanning, "isScanning should be observed true during the scan.")
        _ = await waitUntil(timeout: 20) { !model.isScanning }

        // Then the workspace transitions to the main screen with a plan (ON-06)
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.outcome)
        XCTAssertNotNil(model.plan)
        XCTAssertFalse(model.showOnboarding)
        XCTAssertTrue(model.statusMessage.contains("Scan complete"))
        XCTAssertFalse(model.isScanning)
        XCTAssertGreaterThan(model.plan?.actions.count ?? 0, 0)
    }

    func testScanWithNoFoldersGuardSetsError() async throws {
        // Given a model in folder mode with no folders selected (ON-07)
        let model = try makeModel(defaults: makeDefaultsSuite())
        model.selectedMode = .selectedFolders
        model.selectedFolders = []

        // When the user starts a scan
        model.runScan()
        _ = await waitUntil(timeout: 5) { model.errorMessage != nil }

        // Then the guard surfaces an error and no scan starts
        XCTAssertEqual(model.errorMessage, "Please select folders to scan.")
        XCTAssertNil(model.plan)
        XCTAssertFalse(model.isScanning)
    }

    func testScanFailureKeepsExistingWorkspace() async throws {
        // Given a successful scan that produced a plan (ON-11)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        XCTAssertNotNil(model.plan)
        let originalPlanID = model.plan?.id
        XCTAssertFalse(model.showOnboarding)

        // When a follow-up scan fails because the selected root is gone
        model.selectedFolders = [root.appendingPathComponent("vanished", isDirectory: true)]
        model.runScan()
        let failed = await waitUntil(timeout: 10) { model.errorMessage != nil }
        XCTAssertTrue(failed)
        _ = await waitUntil(timeout: 10) { !model.isScanning }

        // Then the error is surfaced and the previous workspace is retained (ON-11):
        // a failed scan must never bounce the user back to onboarding.
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.statusMessage.contains("Scan failed"))
        XCTAssertNotNil(model.plan)
        XCTAssertEqual(model.plan?.id, originalPlanID, "A failed scan must keep the existing plan.")
        XCTAssertNotNil(model.outcome)
        XCTAssertFalse(model.showOnboarding, "A failed scan must keep the existing workspace.")
    }

    func testCancelScanStopsScanningAndReportsCancelled() async throws {
        // Given a scan over a slightly larger temp tree so there is time to cancel (SP-29)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeTemporaryDirectory(named: "CancelScan")
        for index in 0..<60 {
            _ = try UserStoryFixtures.writeFile("bulk/file-\(index).txt", in: root, data: Data("fixture-\(index)".utf8))
        }
        model.selectedMode = .selectedFolders
        model.selectedFolders = [root]

        // When the user starts a scan and cancels while it is in flight
        model.runScan()
        _ = await waitUntil(timeout: 10) { model.isScanning }
        model.cancelScan()

        // Then the status immediately reflects cancellation; isScanning stays true
        // until the crawl actually unwinds at its next cooperative checkpoint
        // (the UI must not claim idle while disk work continues).
        XCTAssertTrue(model.statusMessage.contains("Cancelling"))
        _ = await waitUntil(timeout: 10) { !model.isScanning && !model.statusMessage.contains("Cancelling") || !model.isScanning }
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.statusMessage, "Scan cancelled.")

        // When the user starts a new scan after cancelling (SP-29/H-01 regression:
        // a cancelled scan's stale task must not repaint or clobber the new scan)
        model.runScan()
        let rescanned = await waitUntil(timeout: 20) { model.plan != nil || model.errorMessage != nil }
        XCTAssertTrue(rescanned, "A new scan after cancel must complete.")
        _ = await waitUntil(timeout: 20) { !model.isScanning }
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.plan)
        XCTAssertFalse(model.isScanning)
    }

    // MARK: - 5. Plan review state machine

    func testApproveRejectAlwaysNeverUpdatePlanState() async throws {
        // Given a scanned plan with several actions
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        let plan = try XCTUnwrap(model.plan)
        XCTAssertGreaterThanOrEqual(plan.actions.count, 4)
        XCTAssertEqual(plan.status, .proposed)

        let actions = plan.actions
        let approved = actions[0]
        let rejected = actions[1]
        let always = actions[2]
        let never = actions[3]

        // When the user reviews each action (PR-03, PR-04, PR-11, PR-12)
        model.approve(approved)
        model.reject(rejected)
        await model.alwaysDoThis(always)
        await model.neverDoThisHere(never)

        // Then every decision is recorded on the plan
        let updatedPlan = try XCTUnwrap(model.plan)
        let byID = Dictionary(uniqueKeysWithValues: updatedPlan.actions.map { ($0.id, $0) })
        XCTAssertEqual(byID[approved.id]?.userDecision, .approved)
        XCTAssertEqual(byID[approved.id]?.status, .approved)
        XCTAssertEqual(byID[rejected.id]?.userDecision, .rejected)
        XCTAssertEqual(byID[rejected.id]?.status, .rejected)
        XCTAssertEqual(byID[always.id]?.userDecision, .alwaysDoThis)
        XCTAssertEqual(byID[always.id]?.status, .approved)
        XCTAssertEqual(byID[never.id]?.userDecision, .neverDoThisHere)
        XCTAssertEqual(byID[never.id]?.status, .rejected)
        XCTAssertEqual(byID[approved.id]?.requiresExplicitConfirmation, true,
                       "An explicit approve gesture is the confirmation for high-risk work (SafetyAuditor gate)")
        XCTAssertEqual(byID[always.id]?.requiresExplicitConfirmation, true,
                       "Always-do-this is an explicit confirmation as well")
        XCTAssertEqual(updatedPlan.status, .partiallyApproved)
    }

    func testPlanMutationsAreNoOpsWithoutPlan() async throws {
        // Given a model that has never scanned
        let model = try makeModel(defaults: makeDefaultsSuite())
        let action = PlannedAction(
            id: "stray", planID: "stray-plan", actionType: .tag, targets: [],
            destination: nil, status: .proposed, risk: .low, confidence: 0.9,
            reason: "stray", userDecision: .undecided, executedAt: nil, findingID: nil
        )

        // When the user tries to review actions without a plan
        model.approve(action)
        await model.alwaysDoThis(action)

        // Then nothing happens and no plan is created
        XCTAssertNil(model.plan)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - 6. Execution

    func testExecuteApprovedTagActionAndUndoRestoresTags() async throws {
        // Given a scanned plan containing an organization tag action (EX-06)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        let tagAction = try XCTUnwrap(model.plan?.actions.first { $0.actionType == .tag })
        let taggedURL = try XCTUnwrap(model.filesByID[tagAction.targets[0]]?.url)

        // When the user approves and executes only the tag action (EX-01)
        model.approve(tagAction)
        await model.executeConfirmedRequest(try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .high)))

        // Then the action completes with an undo record and the file is tagged (EX-12, EX-14)
        XCTAssertFalse(model.isExecuting)
        let summary = try XCTUnwrap(model.executionSummary)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(summary.logs.count, 1)
        XCTAssertEqual(summary.undoRecords.count, 1)
        XCTAssertEqual(model.undoRecords.count, 1)
        XCTAssertEqual(model.plan?.actions.first { $0.id == tagAction.id }?.status, .completed)
        XCTAssertEqual(model.plan?.status, .completed)
        XCTAssertTrue(model.statusMessage.contains("completed"))
        let tagsAfterExecution = readFinderTags(at: taggedURL)
        XCTAssertTrue(tagsAfterExecution.contains("Keep"), "PDF targets map to the 'Keep' taxonomy tag.")

        // When the user undoes the tag (UN-02, UN-12)
        let undoRecord = try XCTUnwrap(model.undoRecords.first)
        await model.restore(undoRecord)

        // Then the tag is removed and the record is marked restored.
        // Note: URLResourceValues.tagNames is nil for untagged files, so treat
        // nil/empty as "no tags".
        XCTAssertEqual(model.statusMessage, "Undo completed.")
        let tagsAfterUndo = readFinderTags(at: taggedURL)
        XCTAssertFalse(tagsAfterUndo.contains("Keep"))
        XCTAssertEqual(model.undoRecords.first?.status, .restored)
    }

    func testExecuteSafeActionsRunsOnlyLowRisk() async throws {
        // Given a scanned plan plus two crafted tag actions at different risk levels
        // against real scanned files
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        let outcome = try XCTUnwrap(model.outcome)
        let lowFile = try XCTUnwrap(outcome.files.first { $0.fileName == "cache.bin" })
        let mediumFile = try XCTUnwrap(outcome.files.first { $0.fileName == "notes.pdf" })
        let lowAction = PlannedAction(
            id: "safe-tag-low", planID: "crafted", actionType: .tag, targets: [lowFile.id],
            destination: nil, status: .proposed, risk: .low, confidence: 0.9,
            reason: "fixture low-risk", userDecision: .undecided, executedAt: nil, findingID: nil
        )
        let mediumAction = PlannedAction(
            id: "safe-tag-medium", planID: "crafted", actionType: .tag, targets: [mediumFile.id],
            destination: nil, status: .proposed, risk: .medium, confidence: 0.9,
            reason: "fixture medium-risk", userDecision: .undecided, executedAt: nil, findingID: nil
        )
        model.plan = Plan(
            id: "crafted-plan", scanSessionID: outcome.session.id, createdAt: Date(),
            status: .proposed, summary: "crafted", estimatedReclaimableBytes: 0,
            estimatedFilesAffected: 2, riskBreakdown: [.low: 1, .medium: 1],
            actions: [lowAction, mediumAction]
        )

        // When the user approves both and executes only safe (low-risk) actions (EX-01)
        model.approve(lowAction)
        model.approve(mediumAction)
        await model.executeConfirmedRequest(try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .low)))

        // Then only the low-risk action ran; the medium-risk one stays approved and pending
        XCTAssertFalse(model.isExecuting)
        let summary = try XCTUnwrap(model.executionSummary)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(summary.logs.count, 1)
        XCTAssertEqual(summary.undoRecords.count, 1)
        XCTAssertEqual(model.undoRecords.count, 1)
        XCTAssertEqual(model.plan?.actions.first { $0.id == lowAction.id }?.status, .completed)
        XCTAssertEqual(model.plan?.actions.first { $0.id == mediumAction.id }?.status, .approved)
        XCTAssertEqual(model.plan?.status, .partiallyApproved)
        XCTAssertTrue(model.statusMessage.contains("Higher-risk approved actions are still pending"))
        let lowTags = readFinderTags(at: lowFile.url)
        XCTAssertTrue(lowTags.contains("Archive Candidate"), "Low-risk tags map to 'Archive Candidate'.")
        let mediumTags = readFinderTags(at: mediumFile.url)
        XCTAssertFalse(mediumTags.contains("Keep"), "The medium-risk action must not run during a safe-only execution.")
        XCTAssertTrue(mediumTags.isEmpty, "The medium-risk file must remain untagged.")
    }

    func testConfirmedExecutionReportsPartialFailureAndKeepsRestoreRecord() async throws {
        let (model, store) = try makeModelWithStore(defaults: makeDefaultsSuite())
        let root = try makeScanFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let didScan = await runScanOnFixture(model, root: root)
        XCTAssertTrue(didScan)
        let outcome = try XCTUnwrap(model.outcome)
        let valid = try XCTUnwrap(outcome.files.first { $0.fileName == "cache.bin" })
        let missing = try XCTUnwrap(outcome.files.first { $0.fileName == "notes.pdf" })
        let actions = [valid, missing].map { file in
            PlannedAction(
                id: file.id, planID: "partial-plan", actionType: .tag, targets: [file.id],
                status: .approved, risk: .low, confidence: 0.99,
                reason: "Disposable confirmation fixture", userDecision: .approved
            )
        }
        model.plan = Plan(
            id: "partial-plan", scanSessionID: outcome.session.id, createdAt: Date(),
            status: .partiallyApproved, summary: "Partial result fixture", estimatedReclaimableBytes: 0,
            estimatedFilesAffected: 2, riskBreakdown: [.low: 2], actions: actions
        )
        model.plan?.originalActions = actions
        let request = try XCTUnwrap(ExecutionRequest(model: model, maximumRisk: .low))
        XCTAssertEqual(request.fileCount, 2)
        XCTAssertEqual(request.unresolvedTargetCount, 0)
        // The plan stays unchanged; executor checks must still detect the missing file.
        try FileManager.default.removeItem(at: missing.url)
        await model.executeConfirmedRequest(request)
        let summary = try XCTUnwrap(model.executionSummary)
        XCTAssertEqual(summary.logs.count, 1)
        XCTAssertEqual(summary.failedActionIDs, [missing.id])
        XCTAssertEqual(model.lastExecutionActionIDs, [valid.id, missing.id])
        XCTAssertEqual(model.plan?.actions.first { $0.id == valid.id }?.status, .completed)
        XCTAssertEqual(model.plan?.actions.first { $0.id == missing.id }?.status, .failed)
        XCTAssertEqual(model.undoRecords.count, 1)
        let reloaded = try makeModel(defaults: makeDefaultsSuite(), store: store)
        await reloaded.loadUndoHistory()
        XCTAssertNil(reloaded.executionSummary)
        XCTAssertEqual(reloaded.historyActions.first { $0.id == valid.id }?.status, .completed)
        XCTAssertEqual(reloaded.historyActions.first { $0.id == missing.id }?.status, .failed)
        model.naturalLanguageCommand = "everything"
        await model.applyNaturalLanguageCommand()
        XCTAssertEqual(model.plan?.actions.first { $0.id == valid.id }?.status, .completed)
        XCTAssertEqual(model.plan?.actions.first { $0.id == missing.id }?.status, .failed)
        XCTAssertTrue(model.pendingExecutableActions().isEmpty, "Planning must not revive completed actions.")
        await model.restore(try XCTUnwrap(model.undoRecords.first))
        XCTAssertEqual(model.undoRecords.first?.status, .restored)
    }

    func testHistoryIncludesCompletedActionsWithoutRestoreRecords() async throws {
        let (model, store) = try makeModelWithStore(defaults: makeDefaultsSuite())
        let root = try makeScanFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let didScan = await runScanOnFixture(model, root: root)
        XCTAssertTrue(didScan)
        var plan = try XCTUnwrap(model.plan)
        plan.actions = [PlannedAction(
            id: "completed-command", planID: plan.id, actionType: .runPackageManagerCleanup,
            targets: ["candidate"], status: .completed, risk: .low, confidence: 1,
            reason: "Previously completed fixture command", userDecision: .approved, executedAt: Date())]
        // A natural-language filter can hide a finished operation from the
        // current list. Its saved original action must remain in History.
        plan.originalActions = plan.actions
        plan.actions = []
        try await store.savePlan(plan)
        let reloaded = try makeModel(defaults: makeDefaultsSuite(), store: store)
        await reloaded.loadUndoHistory()
        XCTAssertTrue(reloaded.undoRecords.isEmpty)
        XCTAssertEqual(reloaded.historyActions.map(\.id), ["completed-command"])
    }

    func testApplicationStagingRequiresApprovalAndRescanAllowsRestaging() async throws {
        let model = try makeModel(defaults: makeDefaultsSuite())
        let root = try makeScanFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Fixture-\(UUID().uuidString).app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let didScan = await runScanOnFixture(model, root: root)
        XCTAssertTrue(didScan)
        model.naturalLanguageCommand = "safe"
        await model.applyNaturalLanguageCommand()
        let originalIDs = Set(model.plan?.actions.map(\.id) ?? [])
        let app = InstalledApplication(
            id: UUID().uuidString, name: bundle.deletingPathExtension().lastPathComponent,
            bundleURL: bundle, bundleIdentifier: nil, bundleSizeBytes: 0)
        await model.stageUninstall(for: app)
        let staged = (model.plan?.actions ?? []).filter { !originalIDs.contains($0.id) }
        XCTAssertFalse(staged.isEmpty)
        XCTAssertTrue(staged.allSatisfy { $0.userDecision == .undecided && $0.executedAt == nil })
        XCTAssertTrue(model.stagedUninstallAppIDs.contains(app.id))
        XCTAssertNil(ExecutionRequest(model: model, maximumRisk: .high))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.path))
        model.naturalLanguageCommand = "everything"
        await model.applyNaturalLanguageCommand()
        let restoredIDs = Set(model.plan?.actions.map(\.id) ?? [])
        XCTAssertTrue(Set(staged.map(\.id)).isSubset(of: restoredIDs))
        let rescanned = await runScanOnFixture(model, root: root)
        XCTAssertTrue(rescanned)
        XCTAssertFalse(model.stagedUninstallAppIDs.contains(app.id))
    }

    func testInspectOnlyActionFailsDuringExecution() async throws {
        // Given a crafted plan with a single inspect-only action against a real scanned file
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        let outcome = try XCTUnwrap(model.outcome)
        let file = try XCTUnwrap(outcome.files.first)
        let inspectAction = PlannedAction(
            id: "inspect-only", planID: "crafted", actionType: .inspectOnly, targets: [file.id],
            destination: nil, status: .proposed, risk: .high, confidence: 0.6,
            reason: "fixture", userDecision: .undecided, executedAt: nil, findingID: nil
        )
        model.plan = Plan(
            id: "crafted-plan", scanSessionID: outcome.session.id, createdAt: Date(),
            status: .proposed, summary: "crafted", estimatedReclaimableBytes: 0,
            estimatedFilesAffected: 1, riskBreakdown: [.high: 1], actions: [inspectAction]
        )

        // When the user approves and executes it
        model.approve(inspectAction)
        await model.executeApprovedActions()

        // Then review-only actions never reach the executor; the UI explains
        // that they were skipped instead of failing (review-wave fix).
        XCTAssertFalse(model.isExecuting)
        XCTAssertNil(model.executionSummary, "Review-only actions must never reach the executor")
        XCTAssertTrue(model.statusMessage.contains("review-only"), "Status must explain the skip: \(model.statusMessage)")
        XCTAssertEqual(model.plan?.actions.first { $0.id == inspectAction.id }?.status, .approved, "Skipped action stays approved")
    }

    // MARK: - 7. Undo wiring

    func testUndoHistoryLoadsAndMissingFileRestoreSetsError() async throws {
        // Given a store with an undo record whose trashed file no longer exists
        let defaults = makeDefaultsSuite()
        let (model, store) = try makeModelWithStore(defaults: defaults)
        let root = try makeTemporaryDirectory(named: "UndoWiring")
        let missingTrashURL = root.appendingPathComponent("Trash/gone.txt", isDirectory: false)
        let restoreTarget = root.appendingPathComponent("Documents/gone.txt", isDirectory: false)
        let record = UndoRecord(
            id: "undo-1", operationLogID: "log-1", inverseAction: .restore,
            restoreURL: restoreTarget, trashURL: missingTrashURL,
            validUntil: nil, status: .available
        )
        try await store.saveUndoRecord(record)

        // When the model loads undo history (UN-01)
        await model.loadUndoHistory()

        // Then the persisted record appears in the model
        XCTAssertEqual(model.undoRecords.count, 1)
        XCTAssertEqual(model.undoRecords.first?.id, "undo-1")

        // When the user tries to restore a record whose file is no longer in Trash (UN-02)
        await model.restore(record)

        // Then the error is surfaced instead of a silent no-op (UN-15)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.errorMessage?.contains("Trash") == true)
    }

    // MARK: - 8. Natural language commands

    func testNaturalLanguageSafeThenEverythingFiltersAndRestores() async throws {
        // Given a scanned plan with a mix of risk levels
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        let originalCount = try XCTUnwrap(model.plan).actions.count
        XCTAssertGreaterThan(originalCount, 1)

        // When the user asks for a safe-only plan (NL-14)
        model.naturalLanguageCommand = "safe"
        await model.applyNaturalLanguageCommand()

        // Then only low-risk actions remain
        let safePlan = try XCTUnwrap(model.plan)
        XCTAssertFalse(safePlan.actions.isEmpty)
        XCTAssertTrue(safePlan.actions.allSatisfy { $0.risk == .low })
        XCTAssertLessThan(safePlan.actions.count, originalCount)
        XCTAssertTrue(model.statusMessage.contains("converted"))

        // When the user asks for everything (NL-15)
        model.naturalLanguageCommand = "everything"
        await model.applyNaturalLanguageCommand()

        // Then the full original action set is restored
        let restoredPlan = try XCTUnwrap(model.plan)
        XCTAssertEqual(restoredPlan.actions.count, originalCount)
        XCTAssertEqual(model.selectedActionID, restoredPlan.actions.first?.id)
    }

    func testNaturalLanguageCommandWithNoPlanIsNoOp() async throws {
        // Given a model that has never scanned (NL-16)
        let model = try makeModel(defaults: makeDefaultsSuite())

        // When a command is applied without a plan
        model.naturalLanguageCommand = "everything"
        await model.applyNaturalLanguageCommand()

        // Then nothing happens
        XCTAssertNil(model.plan)
        XCTAssertNil(model.errorMessage)

        // An empty command is also a no-op (NL-17)
        model.naturalLanguageCommand = "   "
        await model.applyNaturalLanguageCommand()
        XCTAssertNil(model.plan)
    }

    // MARK: - 9. Report generation

    func testGenerateReportWithoutOutcomeShowsGuidance() async throws {
        // Given a model that has never scanned (RP-02)
        let model = try makeModel(defaults: makeDefaultsSuite())

        // When the user requests a report
        await model.generateReport()

        // Then guidance is shown and no report URL is produced
        XCTAssertEqual(model.statusMessage, "Run a scan first to generate a report.")
        XCTAssertNil(model.generatedReportURL)
    }

    func testGenerateReportWithOutcomeWritesToInjectableDestination() async throws {
        // Given a scanned model and an injectable report directory (RP-02)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        let reportDirectory = try makeTemporaryDirectory(named: "ReportDir")

        // When the user generates a report into the temp directory
        await model.generateReport(to: reportDirectory)

        // Then the report PDF is written there and exposed on the model, with no
        // writes to the real home directory
        let reportURL = try XCTUnwrap(model.generatedReportURL)
        XCTAssertTrue(reportURL.path.hasPrefix(reportDirectory.path), "Report must land in the injected destination.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertTrue(model.statusMessage.contains("report generated"))
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - 10. Clear all data

    func testClearAllDataResetsWorkspace() async throws {
        // Given a scanned model with an active selection (ST-11)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        model.naturalLanguageCommand = "cache"
        model.selectedActionID = model.plan?.actions.first?.id
        model.destination = .systemJunk
        model.reviewRiskFilter = .high
        model.searchText = "cache"
        model.exploreViewKindRaw = "sunburst"
        model.stagedUninstallAppIDs = ["old-app"]
        XCTAssertNil(model.errorMessage)

        // When the user clears all data
        await model.clearAllData()

        // Then the workspace returns to onboarding with no plan, outcome, or undo history
        XCTAssertTrue(model.showOnboarding)
        XCTAssertNil(model.plan)
        XCTAssertNil(model.outcome)
        XCTAssertTrue(model.undoRecords.isEmpty)
        XCTAssertTrue(model.historyActions.isEmpty)
        XCTAssertTrue(model.storageSnapshots.isEmpty)
        XCTAssertTrue(model.stagedUninstallAppIDs.isEmpty)
        XCTAssertEqual(model.destination, .overview)
        XCTAssertNil(model.reviewRiskFilter)
        XCTAssertEqual(model.searchText, "")
        XCTAssertEqual(model.exploreViewKindRaw, "list")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.selectedFolders, [])
        XCTAssertEqual(model.selectedMode, .selectedFolders)
        XCTAssertEqual(model.naturalLanguageCommand, "")
        XCTAssertNil(model.generatedReportURL)
        XCTAssertTrue(model.statusMessage.contains("All data cleared"))
    }

    func testClearAllDataClearsAllPersistedPreferences() async throws {
        // Given a model with every preference customized and persisted (ST-18)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        model.selectedMode = .developerCleanup
        model.cleanupPosture = .aggressive
        model.includeAI = true
        model.providerSettings.providerName = "Test Provider"
        model.providerSettings.apiBaseURL = URL(string: "https://example.test/v1")!
        model.providerSettings.textModel = "test-model"
        model.providerSettings.maxTokens = 4096
        model.providerSettings.temperature = 0.9
        model.providerSettings.privacyMode = .snippetsAI
        model.saveSettings()

        // When the user clears all data
        await model.clearAllData()

        // Then every preference resets in memory (ST-18)
        XCTAssertEqual(model.cleanupPosture, .conservative)
        XCTAssertFalse(model.includeAI)
        XCTAssertEqual(model.providerSettings.providerName, "OpenAI-compatible")
        XCTAssertEqual(model.providerSettings.textModel, "gpt-4.1-mini")
        XCTAssertEqual(model.providerSettings.privacyMode, .localOnly)
        XCTAssertEqual(model.selectedMode, .selectedFolders)
        XCTAssertNil(model.errorMessage)

        // And a fresh model against the same suite starts from factory defaults
        let reloaded = try makeModel(defaults: defaults)
        XCTAssertEqual(reloaded.cleanupPosture, .conservative)
        XCTAssertFalse(reloaded.includeAI)
        XCTAssertEqual(reloaded.providerSettings.providerName, "OpenAI-compatible")
        XCTAssertEqual(reloaded.providerSettings.privacyMode, .localOnly)
        XCTAssertEqual(reloaded.selectedMode, .selectedFolders)
    }

    func testSaveAPIKeyDoesNotOverridePrivacyMode() async throws {
        // G-04: saving an API key must never silently change the user's chosen
        // privacy mode (previously forced .metadataOnlyAI).
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        model.apiKeyInput = "sk-test-\(UUID().uuidString)"
        model.providerSettings.privacyMode = .localOnly
        model.includeAI = false

        // When the user saves a key while staying in Local Only mode
        await model.saveAPIKey()

        // Then the privacy mode is untouched, AI features are enabled, and the
        // status message surfaces the current mode
        XCTAssertEqual(model.providerSettings.privacyMode, .localOnly, "Saving a key must not override privacy mode.")
        XCTAssertTrue(model.includeAI, "Saving a key enables AI features.")
        XCTAssertTrue(model.statusMessage.contains("API key saved"))
        XCTAssertTrue(model.statusMessage.contains("Local Only"))
        XCTAssertNil(model.errorMessage)

        // Clean up the test key from the real keychain
        try? await KeychainStore(inMemory: true).deleteAPIKey()
    }

    func testScanSummaryToastUsesCompactDurationFormat() async throws {
        // G-04: the completion toast must use a compact duration ("3s", "1m 12s")
        // instead of DateComponentsFormatter's locale-dependent "0 secs" output,
        // with a space before the candidate count.
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        let summary = try XCTUnwrap(model.activeScanSummary)
        XCTAssertTrue(summary.hasPrefix("What changed? "))
        XCTAssertFalse(summary.contains("secs"), "Toast must not use the 'secs' unit; got: \(summary)")
        let actionCount = try XCTUnwrap(model.plan).actions.count
        XCTAssertTrue(summary.contains(", \(actionCount) candidates"), "Toast must keep the space-separated candidate count; got: \(summary)")
    }

    // MARK: - 11. Reset / state hygiene

    func testNewScanResetsExecutionState() async throws {
        // Given a model with a completed execution cycle (EX-11)
        let defaults = makeDefaultsSuite()
        let model = try makeModel(defaults: defaults)
        let root = try makeScanFixtureRoot()
        let completed = await runScanOnFixture(model, root: root)
        XCTAssertTrue(completed)
        if let tagAction = model.plan?.actions.first(where: { $0.actionType == .tag }) {
            model.approve(tagAction)
            await model.executeApprovedActions()
        }
        XCTAssertNotNil(model.executionSummary)
        XCTAssertNotNil(model.executionSummary?.undoRecords)
        let firstPlanID = model.plan?.id

        // When a new scan runs
        model.runScan()
        let replaced = await waitUntil(timeout: 20) { model.plan?.id != firstPlanID || model.errorMessage != nil }
        XCTAssertTrue(replaced, "The second scan should replace the plan.")
        _ = await waitUntil(timeout: 20) { !model.isScanning }

        // Then the previous execution state is cleared and the plan is replaced.
        // Note: undoRecords intentionally persist (undo history is app-wide, not scan-scoped).
        XCTAssertNil(model.executionSummary)
        XCTAssertEqual(model.executionProgress, 0)
        XCTAssertEqual(model.executionCompletedActions, 0)
        XCTAssertFalse(model.isExecuting)
        XCTAssertNotNil(model.plan)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - 12. Settings window helpers

    func testApplyCalibrationPresetUpdatesStatusMessage() async throws {
        // Given a model with an in-memory store (ST-13..ST-16)
        let model = try makeModel(defaults: makeDefaultsSuite())

        // When the user applies a calibration preset
        await model.applyCalibrationPreset("Never delete design source")

        // Then the confirmation message is shown
        XCTAssertEqual(model.statusMessage, "Preference saved.")
        XCTAssertNil(model.errorMessage)
    }
}
