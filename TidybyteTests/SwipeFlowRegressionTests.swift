import XCTest
import SwiftData
@testable import Tidybyte

/// Regression coverage for the swipe-flow audit fixes: back-to-back swipes
/// (SWIPE-05), picker-guarded undo (SWIPE-06), pending-deletion exposure
/// (SWIPE-02), retry state reset (SWIPE-09), predicate-based swipe-record
/// upsert (SWIPE-03), and the empty-commit no-op (SWIPE-08).
@MainActor
final class SwipeFlowRegressionTests: XCTestCase {

    // Held for the lifetime of the test so the in-memory store (and the view
    // model's ModelContext, which is this container's mainContext) stays valid.
    private var container: ModelContainer!

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeViewModel(assetCount: Int = 3) throws -> SwipeSessionViewModel {
        let schema = Schema([SwipeRecord.self, CompressionRecord.self, StorageSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let viewModel = SwipeSessionViewModel(
            filter: .allMedia,
            photoService: PhotoLibraryService(),
            modelContext: container.mainContext
        )
        viewModel.assets = (0..<assetCount).map { makeAsset(id: "asset-\($0)") }
        return viewModel
    }

    // MARK: - SWIPE-05: back-to-back swipes

    /// A swipe applies its decision at commit time (the fling is only visual),
    /// so two fast swipes must each land on their own card.
    func testBackToBackSwipesAttributeToTheirOwnCards() throws {
        let vm = try makeViewModel()

        vm.swipeLeft()
        vm.swipeRight()

        XCTAssertEqual(vm.currentIndex, 2)
        XCTAssertEqual(vm.pendingDeletionIds, ["asset-0"])
        XCTAssertEqual(vm.undoStack.map(\.asset.id), ["asset-0", "asset-1"])
        XCTAssertEqual(vm.undoStack.map(\.decision), [.deleted, .kept])
    }

    func testSwipeDirectionCommitPolicy() {
        let width: CGFloat = 300 // commit threshold 120
        func resolve(_ t: CGSize, _ p: CGSize = .zero) -> SwipeDirection? {
            SwipeDirection.resolve(translation: t, predicted: p, cardWidth: width)
        }
        XCTAssertEqual(resolve(CGSize(width: 130, height: 0)), .keep)
        XCTAssertEqual(resolve(CGSize(width: -130, height: 0)), .delete)
        XCTAssertEqual(resolve(CGSize(width: 40, height: 0), CGSize(width: 600, height: 0)), .keep, "A fast flick commits")
        XCTAssertEqual(resolve(CGSize(width: -130, height: -130)), .delete, "A diagonal drag resolves horizontally")
        XCTAssertEqual(resolve(CGSize(width: 10, height: -130)), .album)
        XCTAssertNil(resolve(CGSize(width: 60, height: -60)), "A short drag snaps back")
    }

    func testFlingVelocityIsRelativeAndClamped() {
        let start = CGSize(width: 100, height: 0)
        let target = SwipeDirection.keep.flingOffset(from: start, distance: 1000)
        XCTAssertEqual(target, CGSize(width: 1000, height: 0))
        XCTAssertEqual(SwipeDirection.relativeVelocity(CGSize(width: 1800, height: 0), from: start, to: target), 2, accuracy: 0.001)
        XCTAssertEqual(SwipeDirection.relativeVelocity(CGSize(width: -500, height: 0), from: start, to: target), 0, "A throw against the direction starts from rest")
        XCTAssertEqual(SwipeDirection.relativeVelocity(CGSize(width: 90_000, height: 0), from: start, to: target), 10)
    }

    // MARK: - SWIPE-06: undo blocked while album picker is presented

    func testUndoIsBlockedWhileAlbumPickerPresented() async throws {
        let vm = try makeViewModel()
        vm.swipeLeft() // deletion pending → undo stack non-empty
        XCTAssertEqual(vm.undoStack.count, 1)

        vm.keepWithAlbum() // opens the album picker for the next card
        XCTAssertTrue(vm.showAlbumPicker)

        await vm.undo() // must be a no-op: the deck must not rewind under the sheet

        XCTAssertEqual(vm.undoStack.count, 1, "Undo must not consume the entry while the picker is up")
        XCTAssertEqual(vm.currentIndex, 1, "The deck must not rewind while the picker is presented (it also does not advance until the album choice is resolved)")
        XCTAssertEqual(vm.pendingDeletionIds, ["asset-0"], "Pending deletions must be untouched")
    }

    // MARK: - SWIPE-02: pending-deletion exposure

    func testHasPendingDeletionsReflectsPendingIdsAndCommitState() throws {
        let vm = try makeViewModel()
        XCTAssertFalse(vm.hasPendingDeletions)

        vm.swipeLeft()
        XCTAssertTrue(vm.hasPendingDeletions)

        vm.deletionCommitted = true
        XCTAssertFalse(vm.hasPendingDeletions, "Committed deletions are no longer pending")

        vm.deletionCommitted = false
        vm.discardPendingDeletions()
        XCTAssertFalse(vm.hasPendingDeletions, "Discarded deletions are no longer pending")
    }

    // MARK: - SWIPE-09: retry resets load state

    func testRetryLoadClearsLoadedState() throws {
        let vm = try makeViewModel()
        // `hasLoadedInitialAssets` starts false and is private(set); the
        // meaningful regression is that retryLoad() resets the derived states
        // so loadAssetsIfNeeded() will re-run.
        vm.allPhotosAlreadySwiped = true
        vm.isLoading = true

        vm.retryLoad()

        XCTAssertFalse(vm.hasLoadedInitialAssets, "Retry must force a fresh load")
        XCTAssertFalse(vm.allPhotosAlreadySwiped)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - SWIPE-03: predicate-based upsert round-trip

    func testSwipeRecordUpsertRoundTrip() throws {
        let vm = try makeViewModel()

        vm.skip() // asset-0: insert via the predicate-based fetch

        let records = try container.mainContext.fetch(FetchDescriptor<SwipeRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.assetLocalIdentifier, "asset-0")
        XCTAssertEqual(records.first?.decision, .skipped)

        vm.skip() // asset-1: second id, second insert
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SwipeRecord>()).count, 2)
    }

    func testSwipeRecordUpsertUpdatesExistingRecordViaPredicate() throws {
        let vm = try makeViewModel()

        vm.skip() // asset-0
        vm.currentIndex = 0 // rewind to the same asset
        vm.skip() // same asset again — must update in place, not duplicate

        let records = try container.mainContext.fetch(FetchDescriptor<SwipeRecord>())
        XCTAssertEqual(records.count, 1, "Re-skipping the same asset must upsert, not insert a duplicate")
        XCTAssertEqual(records.first?.assetLocalIdentifier, "asset-0")
    }

    // MARK: - SWIPE-08: empty commit is a no-op

    func testCommitDeletionsWithNoPendingIsNoOp() async throws {
        let vm = try makeViewModel()
        XCTAssertFalse(vm.deletionCommitted)

        await vm.commitDeletions()

        XCTAssertFalse(vm.deletionCommitted, "Committing zero pending deletions must be a no-op")
        XCTAssertFalse(vm.isDeletingBatch)
        XCTAssertFalse(vm.hasPendingDeletions)
    }

    // MARK: - Helpers

    private func makeAsset(id: String) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: .photo,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: 4032,
            pixelHeight: 3024,
            duration: 0,
            fileSize: 8_000_000,
            filename: "\(id).jpg",
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: false,
            isScreenshot: false,
            isLocallyAvailable: true
        )
    }
}
