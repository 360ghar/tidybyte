import XCTest
import SwiftData
@testable import Tidybyte

/// Covers the deferred-deletion, undo, and discard logic in the swipe session —
/// including the regression guard that a left-swipe must NOT persist a SwipeRecord
/// (otherwise an uncommitted deletion would silently hide a photo that still exists).
@MainActor
final class SwipeSessionDeletionTests: XCTestCase {

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

    private func swipeRecordCount() throws -> Int {
        try container.mainContext.fetch(FetchDescriptor<SwipeRecord>()).count
    }

    func testSwipeLeftDefersDeletionAndWritesNoSwipeRecord() throws {
        let vm = try makeViewModel()

        vm.swipeLeft()

        XCTAssertEqual(vm.pendingDeletionIds, ["asset-0"])
        XCTAssertEqual(vm.sessionStats.deletedCount, 1)
        XCTAssertEqual(vm.currentIndex, 1)
        // The crux of the silent-hiding fix: nothing persisted until commit.
        XCTAssertEqual(try swipeRecordCount(), 0)
    }

    func testSwipeLeftDoesNotDoubleCountAlreadyPendingAsset() throws {
        let vm = try makeViewModel()
        vm.pendingDeletionIds = ["asset-0"]
        vm.sessionStats.deletedCount = 0 // simulate id already pending without stats

        vm.swipeLeft() // asset-0 is current and already pending

        XCTAssertEqual(vm.pendingDeletionIds, ["asset-0"], "Should not append a duplicate id")
        XCTAssertEqual(vm.sessionStats.deletedCount, 0, "Should not double-count an already-pending asset")
        XCTAssertEqual(vm.currentIndex, 1, "Should still advance")
    }

    func testSkipPersistsSwipeRecord() throws {
        let vm = try makeViewModel()

        vm.skip()

        XCTAssertEqual(vm.sessionStats.skippedCount, 1)
        XCTAssertEqual(vm.currentIndex, 1)
        let records = try container.mainContext.fetch(FetchDescriptor<SwipeRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.assetLocalIdentifier, "asset-0")
        XCTAssertEqual(records.first?.decision, .skipped)
    }

    func testSwipeRightIsNoOpWhileAKeepIsPending() throws {
        let vm = try makeViewModel()

        vm.swipeRight()
        XCTAssertEqual(vm.pendingKeepAsset?.id, "asset-0")
        XCTAssertTrue(vm.showAlbumPicker)

        // Advance the deck underneath and try again; the pending keep must not be clobbered.
        vm.currentIndex = 1
        vm.swipeRight()
        XCTAssertEqual(vm.pendingKeepAsset?.id, "asset-0", "A second right-swipe must not overwrite the pending keep")
    }

    func testRightSwipeOnAssetAlreadyInAlbumSkipsPickerAndKeeps() throws {
        let vm = try makeViewModel()
        vm.assetIdsInUserAlbums = ["asset-0"]

        vm.swipeRight()

        XCTAssertFalse(vm.showAlbumPicker, "Already-organized photo should not prompt the picker")
        XCTAssertNil(vm.pendingKeepAsset)
        XCTAssertEqual(vm.sessionStats.organizedCount, 1)
        XCTAssertEqual(vm.sessionStats.skippedCount, 0)
        XCTAssertEqual(vm.currentIndex, 1, "Should advance to the next card")
        let records = try container.mainContext.fetch(FetchDescriptor<SwipeRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.assetLocalIdentifier, "asset-0")
        XCTAssertEqual(records.first?.decision, .kept)
    }

    func testUndoOfDeleteRestoresStateAndKeepsNoRecord() async throws {
        let vm = try makeViewModel()
        vm.swipeLeft()

        await vm.undo()

        XCTAssertTrue(vm.pendingDeletionIds.isEmpty)
        XCTAssertEqual(vm.sessionStats.deletedCount, 0)
        XCTAssertEqual(vm.sessionStats.deletedBytes, 0)
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertEqual(try swipeRecordCount(), 0)
    }

    func testDiscardPendingDeletionsClearsState() throws {
        let vm = try makeViewModel()
        vm.swipeLeft()
        vm.swipeLeft()
        XCTAssertEqual(vm.pendingDeletionIds.count, 2)

        vm.discardPendingDeletions()

        XCTAssertTrue(vm.pendingDeletionIds.isEmpty)
        XCTAssertEqual(vm.pendingDeletionBytes, 0)
        XCTAssertEqual(vm.sessionStats.deletedCount, 0)
        XCTAssertEqual(vm.sessionStats.deletedBytes, 0)
    }

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
