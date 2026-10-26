import XCTest
import SwiftData
@testable import Tidybyte

/// Regression coverage for the audit fixes. Each test names the defect it pins,
/// because every one of them was silent: the app kept running and the wrong
/// state was simply never surfaced.
@MainActor
final class AuditRegressionTests: XCTestCase {

    private var containers: [ModelContainer] = []

    override func tearDown() async throws {
        CleanupLedger.shared.detach()
        containers = []
        try await super.tearDown()
    }

    private func makeContainer(_ models: [any PersistentModel.Type]) throws -> ModelContainer {
        let schema = Schema(models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        containers.append(container)
        return container
    }

    private func makeSession(in container: ModelContainer) -> SwipeSessionViewModel {
        SwipeSessionViewModel(
            filter: .allMedia,
            photoService: PhotoLibraryService(),
            modelContext: container.mainContext
        )
    }

    // MARK: - F1: a hosted session's pending deletions survive external navigation

    /// The cleanup stack owns the session view model, so collapsing it
    /// (`cleanupPath.removeAll()`) destroys the model and the marked-but-
    /// uncommitted ids with it. An external request must be parked, not applied.
    func testCleanupHostedSessionParksTheRequestAndKeepsItsStack() throws {
        let container = try makeContainer([SwipeRecord.self])
        let session = makeSession(in: container)
        let navigation = AppNavigation()
        navigation.selectedTab = .cleanup
        navigation.cleanupPath = [.screenshots]
        navigation.setActiveSwipeSession(session)
        session.pendingDeletionIds = ["asset-0"]

        navigation.handle(.cleanupHome)

        XCTAssertEqual(
            navigation.cleanupPath,
            [.screenshots],
            "the stack hosting the session must not collapse under its pending deletions"
        )
        XCTAssertEqual(navigation.selectedTab, .cleanup, "a parked request does not navigate")
        XCTAssertEqual(navigation.deferredLink, .cleanupHome)
        XCTAssertTrue(session.deletionReviewRequested, "the user is routed to the review instead")
    }

    /// The parked request is not lost: once nothing is pending, it applies.
    func testParkedRequestAppliesOnceNothingIsPending() throws {
        let container = try makeContainer([SwipeRecord.self])
        let session = makeSession(in: container)
        let navigation = AppNavigation()
        navigation.selectedTab = .cleanup
        navigation.cleanupPath = [.screenshots]
        navigation.setActiveSwipeSession(session)
        session.pendingDeletionIds = ["asset-0"]

        navigation.handle(.cleanupHome)
        XCTAssertEqual(navigation.cleanupPath, [.screenshots], "still parked")

        session.pendingDeletionIds = []
        navigation.applyDeferredLinkIfPossible()

        XCTAssertEqual(navigation.cleanupPath, [], "the replay lands the original request")
        XCTAssertNil(navigation.deferredLink)
        XCTAssertEqual(navigation.selectedTab, .cleanup)
    }

    /// A session without pending deletions never blocks navigation.
    func testNavigationIsNotParkedWithoutPendingDeletions() throws {
        let container = try makeContainer([SwipeRecord.self])
        let session = makeSession(in: container)
        let navigation = AppNavigation()
        navigation.cleanupPath = [.screenshots]
        navigation.setActiveSwipeSession(session)

        navigation.handle(.cleanupHome)

        XCTAssertEqual(navigation.cleanupPath, [])
        XCTAssertNil(navigation.deferredLink)
        XCTAssertFalse(session.deletionReviewRequested)
    }

    /// A request parked before the user finished the review must not replay over
    /// the destination they chose afterwards. Replaying it there would be the
    /// same navigation surprise this fix removes, just one screen later.
    func testAParkedRequestDoesNotOverrideTheUsersOwnExit() throws {
        let container = try makeContainer([SwipeRecord.self])
        let session = makeSession(in: container)
        let navigation = AppNavigation()
        navigation.selectedTab = .cleanup
        navigation.cleanupPath = [.screenshots]
        navigation.setActiveSwipeSession(session)
        session.pendingDeletionIds = ["asset-0"]

        navigation.handle(.cleanupHome)
        XCTAssertEqual(navigation.deferredLink, .cleanupHome)

        // The user commits the deletions, then taps the completion screen's
        // "Back to Swipe Home".
        session.pendingDeletionIds = []
        navigation.returnToSwipeHome()

        XCTAssertEqual(navigation.selectedTab, .swipe)
        XCTAssertNil(navigation.deferredLink, "the user's own choice supersedes the parked request")

        navigation.cleanupPath = []
        navigation.applyDeferredLinkIfPossible()
        XCTAssertEqual(navigation.selectedTab, .swipe, "nothing replays after an explicit exit")
    }

    /// Same rule for a tab tap, which bypasses `handle` entirely: the request
    /// parked behind the review must not resurface when the user later pops the
    /// cleanup stack.
    func testATabTapAlsoRetiresAParkedRequest() throws {
        let container = try makeContainer([SwipeRecord.self])
        let session = makeSession(in: container)
        let navigation = AppNavigation()
        navigation.selectedTab = .cleanup
        navigation.cleanupPath = [.screenshots]
        navigation.setActiveSwipeSession(session)
        session.pendingDeletionIds = ["asset-0"]

        navigation.handle(.storage)
        XCTAssertEqual(navigation.deferredLink, .storage)

        navigation.selectTabManually(.settings)
        XCTAssertNil(navigation.deferredLink, "a tab tap retires the parked request")
        XCTAssertEqual(navigation.selectedTab, .settings)

        session.pendingDeletionIds = []
        navigation.cleanupPath = []
        navigation.applyDeferredLinkIfPossible()
        XCTAssertEqual(navigation.selectedTab, .settings, "the tab the user picked stands")
    }

    // MARK: - F2: declining "Remove Copies" must leave the swap promotable

    /// `finalizeOriginalKept(copyRemoved: false)` used to claim `finish()` and
    /// then delegate to `finalizeKeptBoth()`, which is documented as NOT
    /// consuming it. The later Try Again then failed its `guard finish()`, so
    /// the row stayed `.kept` with zero saved bytes for good and both History
    /// and lifetime-freed under-reported the compression permanently.
    func testDecliningRemoveCopiesStillAllowsTryAgainToFinalizeCompleted() throws {
        let container = try makeContainer([CompressionRecord.self])
        let context = container.mainContext
        let swap = try CompressionSwap(
            mediaType: .photo,
            assetId: "kept-then-retried",
            originalSize: 100,
            exportPreset: "720p",
            modelContext: context
        )
        swap.recordReplacement(id: "copy-1", size: 50)

        // Decline path as the alert runs it: settle kept-both, then the user
        // also declines "Remove Copies".
        swap.finalizeKeptBoth()
        swap.finalizeOriginalKept(copyRemoved: false)

        // Try Again succeeds.
        swap.finalizeCompleted(compressedSize: 50)

        let records = try context.fetch(FetchDescriptor<CompressionRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.outcome, CompressionOutcome.completed.rawValue)
        XCTAssertEqual(records.first?.savedBytes, 50, "the promotion must carry the saved bytes")
    }

    /// The branch that DOES consume the finish must still settle as skipped and
    /// release the live swap, so reconcile can take the row.
    func testRemovingTheCopyStillSettlesSkippedAndReleasesTheSwap() throws {
        let container = try makeContainer([CompressionRecord.self])
        let context = container.mainContext
        let swap = try CompressionSwap(
            mediaType: .photo,
            assetId: "copy-removed",
            originalSize: 100,
            exportPreset: "720p",
            modelContext: context
        )
        swap.recordReplacement(id: "copy-1", size: 50)

        swap.finalizeOriginalKept(copyRemoved: true)

        let records = try context.fetch(FetchDescriptor<CompressionRecord>())
        XCTAssertEqual(records.first?.outcome, CompressionOutcome.skipped.rawValue)
        XCTAssertNil(records.first?.replacementAssetLocalIdentifier)
        XCTAssertFalse(CompressionSwap.isLive(assetId: "copy-removed"))
    }

    // MARK: - F3: deletes in the compression tools reach the ledger

    /// A partial failure used to be thrown away: the confirmed deletions stayed
    /// in the list and no ledger row recorded them. The shared pipeline applies
    /// only what PhotoKit confirmed and logs exactly that.
    func testPartialFailureReconcilesAndRecordsOnlyConfirmedIds() async throws {
        let container = try makeContainer([CleanupActivityRecord.self, CompressionRecord.self])
        CleanupLedger.shared.attach(modelContext: container.mainContext)

        var applied: Set<String> = []
        var recorded: Int?
        let outcome = await CleanupDeletion.delete(
            requestedIds: ["gone", "ok", "blocked"],
            kind: .photoCompression,
            sizeById: ["gone": 1_000, "ok": 5_000, "blocked": 1_000],
            performDelete: { _ in
                throw PhotoServiceError.partialDeletion(
                    succeededIds: ["ok"],
                    failedCount: 1,
                    alreadyAbsentIds: ["gone"]
                )
            },
            apply: { applied = $0 },
            recordDeleted: { recorded = $0 }
        )

        XCTAssertEqual(applied, ["ok", "gone"], "confirmed and already-absent ids both leave the list")
        XCTAssertEqual(recorded, 1)
        XCTAssertNotNil(outcome.errorMessage, "a partial failure still reports itself")

        let rows = try container.mainContext.fetch(FetchDescriptor<CleanupActivityRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, CleanupActivityKind.photoCompression.rawValue)
        XCTAssertEqual(rows.first?.itemCount, 1, "only the confirmed deletion is counted")
        XCTAssertEqual(rows.first?.freedBytes, 5_000)
    }

    /// The compression kinds are written by the ledger for plain per-row deletes
    /// AND folded from successful `CompressionRecord` rows. Those are different
    /// events — a whole original versus an original-minus-copy delta — so the
    /// tool's row has to sum them, not let one shadow the other.
    func testCompressionDeletesAndCompressionsAreSeparateLedgerEvents() throws {
        let activity = [
            CleanupActivityRecord(
                kind: CleanupActivityKind.photoCompression.rawValue,
                itemCount: 2,
                freedBytes: 5_000,
                recordedAt: Date(timeIntervalSince1970: 1_000)
            )
        ]
        let compressions = [
            CompressionRecord(
                assetLocalIdentifier: "compressed",
                originalSizeBytes: 1_000,
                compressedSizeBytes: 400,
                exportPreset: "720p",
                outcome: CompressionOutcome.completed.rawValue,
                // Defaults to "video"; the delete under test is a photo one.
                mediaType: CompressionMediaType.photo.rawValue
            )
        ]

        let summary = CleanupActivitySummary.build(
            events: CleanupLedger.events(activityRecords: activity, compressionRecords: compressions)
        )

        let row = summary.byTool.first { $0.kind == .photoCompression }
        XCTAssertEqual(row?.bytes, 5_600)
        XCTAssertEqual(row?.count, 3)
        XCTAssertEqual(summary.lifetimeItemCount, 3)
    }

    // MARK: - F4: the Live Photo delete tally belongs to one visit

    /// `deletedCount` was only ever incremented, so a re-fetched list of Live
    /// Photos still carried a red "Deleted N" from a previous pass under a
    /// freshly built header.
    func testRefreshClearsTheSessionDeleteTally() async {
        let viewModel = LivePhotosConverterViewModel()
        viewModel.deletedCount = 3

        await viewModel.refresh()

        XCTAssertEqual(viewModel.deletedCount, 0)
    }

    // MARK: - F5: a collapsed burst says so on both delete paths

    /// Deleting one frame collapses a two-frame burst, which then drops out of
    /// the list. The single-delete path did that silently while Auto-Clean
    /// announced it; both now share one notice.
    func testCollapseNoticeIsSharedAndSilentWhenNothingCollapses() {
        XCTAssertNil(BurstCleanerViewModel.collapseNotice(burstCount: 0))
        XCTAssertEqual(
            BurstCleanerViewModel.collapseNotice(burstCount: 1),
            L10n.string("1 burst cleaned down to a single photo."),
            "one collapsed burst reads as a sentence, not a counted template"
        )
        XCTAssertEqual(
            BurstCleanerViewModel.collapseNotice(burstCount: 3),
            L10n.format("%lld bursts cleaned down to single photos.", 3)
        )
    }

    // MARK: - R1: both album sheets share one empty-reason rule

    /// The two album sheets carried near-identical copies of this. The shared
    /// loader asks for a census only when the list is empty — on a non-empty
    /// list the reason cannot change what is drawn — and the answer then splits
    /// on what is actually missing under limited access.
    func testAlbumSheetLoaderOnlyAsksForACensusWhenTheListIsEmpty() async {
        var censusCalls = 0
        let populated = await AlbumSheetLoader.load(
            fetchAlbums: { [AlbumInfo(id: "a", title: "Camera", count: 3, type: .userAlbum)] },
            census: {
                censusCalls += 1
                return 0
            },
            authorizationStatus: { .authorized }
        )
        XCTAssertNil(populated.emptyReason)
        XCTAssertEqual(censusCalls, 0, "a non-empty list needs no census")

        let empty = await AlbumSheetLoader.load(
            fetchAlbums: { [] },
            census: {
                censusCalls += 1
                return 0
            },
            authorizationStatus: { .limited }
        )
        XCTAssertEqual(censusCalls, 1)
        XCTAssertEqual(
            empty.emptyReason,
            .limitedNoSelection,
            "limited access with nothing shared is a picker problem, not an album problem"
        )
    }

    /// Photos visible under limited access: the user albums are the missing
    /// part, so the card must offer Full Access and not "share more photos".
    func testAlbumSheetLoaderWithVisiblePhotosBlamesTheMissingUserAlbums() async {
        let result = await AlbumSheetLoader.load(
            fetchAlbums: { [] },
            census: { 42 },
            authorizationStatus: { .limited }
        )

        XCTAssertEqual(result.emptyReason, .limitedCannotUseAlbums)
        XCTAssertEqual(result.emptyReason?.recovery, .limitedAlbumsNeedFullAccess)
    }

    // MARK: - C1/C2: one scan at a time, and a cancelled scan cannot resurrect

    /// The two races `ScanRunner` exists to prevent: a second `start` used to
    /// launch a second run, and a cancelled run's queued progress write flipped
    /// the state back to `.scanning` with nothing behind it.
    func testCancelledScanCannotResurrectOrClobberTheNextRun() async {
        let runner = ScanRunner()
        var state: ScanState = .idle
        var firstToken: Int?
        let started = expectation(description: "first run started")
        let secondRan = expectation(description: "second run started")

        runner.start { token in
            firstToken = token
            started.fulfill()
            // Parks until cancelled; a scan in flight is a cancellable wait.
            try? await Task.sleep(for: .seconds(30))
        }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(runner.isRunning)

        runner.start { _ in
            XCTFail("a second start while a run is in flight must be a no-op")
        }

        runner.cancel()
        state = .idle
        XCTAssertFalse(runner.isRunning, "cancel releases the slot immediately")

        if let staleToken = firstToken {
            runner.update(staleToken) { state = .completed }
        } else {
            XCTFail("the first run never received a token")
        }
        XCTAssertEqual(state, .idle, "a post-cancel write must be dropped (C2)")

        runner.start { _ in secondRan.fulfill() }
        await fulfillment(of: [secondRan], timeout: 5)
        // The wrapper clears the handle after `work` returns, on the main actor,
        // so poll instead of assuming a fixed number of yields is enough — a
        // fixed count is exactly the kind of timing assumption that turns a
        // regression test into a flake on a loaded CI machine.
        let released = await waitUntil(timeout: 2) { !runner.isRunning }
        XCTAssertTrue(released, "a finished run releases its own slot (C1)")
    }

    // MARK: - Launch offer: waiting for a dismissing cover

    /// The launch offer is triggered the instant `hasCompletedOnboarding` flips,
    /// which is while onboarding's `fullScreenCover` is still dismissing. A
    /// single snapshot check returned false on that frame and nothing
    /// re-triggered it, so the launch's only offer was dropped.
    func testTheReadinessWaitOutlastsADismissingCover() async {
        var checks = 0
        let ready = await PhotoPermissionHandler.waitUntilReadyToPresent(
            timeout: .seconds(2),
            pollInterval: .milliseconds(5),
            // False for the first three samples, like a cover mid-dismissal.
            isReady: {
                checks += 1
                return checks > 3
            }
        )
        XCTAssertTrue(ready, "the wait must outlast a cover that is still dismissing")
        XCTAssertEqual(checks, 4, "it returns on the first ready sample, not at the timeout")
    }

    func testTheReadinessWaitGivesUpInsteadOfHoldingTheTask() async {
        let start = ContinuousClock.now
        let ready = await PhotoPermissionHandler.waitUntilReadyToPresent(
            timeout: .milliseconds(60),
            pollInterval: .milliseconds(10),
            isReady: { false }
        )
        let elapsed = ContinuousClock.now - start
        XCTAssertFalse(ready, "a stuck presentation must not report ready")
        XCTAssertLessThan(elapsed, .seconds(2), "the wait is bounded, so it cannot hold a launch forever")
    }

    /// Polls `condition` on the main actor until it holds or the timeout
    /// elapses, yielding between checks so the tasks under test can run.
    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }
}
