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
        // The fixtures are complete summaries already; keep PhotoKit out of it.
        viewModel.loadDetails = { _ in [:] }
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

    func testKeepAfterMarkRemovesPendingDeletion() throws {
        let vm = try makeViewModel()
        vm.pendingDeletionIds = ["asset-0"]
        vm.pendingDeletionSizeById = ["asset-0": 8_000_000]
        vm.sessionStats.deletedCount = 1

        vm.swipeRight() // asset-0 is current: the user now keeps it

        XCTAssertTrue(vm.pendingDeletionIds.isEmpty, "A kept photo must not stay on the delete list")
        XCTAssertEqual(vm.pendingDeletionBytes, 0)
        XCTAssertEqual(vm.sessionStats.deletedCount, 0)
    }

    func testDeckShowsOneFramePerBurstPreferringPicks() {
        func frame(_ id: String, burst: String?, pick: BurstPick = .none) -> AssetSummary {
            var asset = AssetSummary(
                id: id, mediaType: .photo, creationDate: nil, modificationDate: nil,
                pixelWidth: 100, pixelHeight: 100, duration: 0, fileSize: 1_000,
                filename: nil, isFavorite: false, isBurst: burst != nil, burstIdentifier: burst,
                isLivePhoto: false, isScreenshot: false, isLocallyAvailable: true
            )
            asset.burstPick = pick
            return asset
        }
        let deck = SwipeSessionViewModel.collapsingBursts([
            frame("solo", burst: nil),
            frame("b1-first", burst: "b1"),
            frame("b1-auto", burst: "b1", pick: .iPhone),
            frame("b2-first", burst: "b2"),
            frame("b2-second", burst: "b2")
        ])
        XCTAssertEqual(deck.map(\.id), ["solo", "b1-auto", "b2-first"])
    }

    func testDeckReloadExcludesPendingDeletions() {
        let assets = ["a", "b", "c"].map(makeAsset(id:))
        let deck = SwipeSessionViewModel.deckAssets(assets, excludingPending: ["b"])
        XCTAssertEqual(deck.map(\.id), ["a", "c"])
    }

    /// Swipes faster than the background detail window can load: every
    /// deletion must still be recorded with the photo's real size.
    func testSwipesThatOutrunTheDetailWindowStillRecordSizes() throws {
        let vm = try makeViewModel(assetCount: 0)
        vm.assets = (0..<60).map { makeListing(id: "asset-\($0)") }
        let library = Dictionary(uniqueKeysWithValues: vm.assets.map { ($0.id, makeAsset(id: $0.id)) })
        vm.loadDetails = { ids in library.filter { ids.contains($0.key) } }

        vm.skip() // card 0 is shown before any window is loaded
        for _ in 1..<50 { vm.swipeLeft() } // no await: the async window never lands

        XCTAssertEqual(vm.pendingDeletionIds.count, 49)
        XCTAssertEqual(vm.sessionStats.deletedBytes, 49 * 8_000_000)
        XCTAssertEqual(vm.pendingDeletionBytes, 49 * 8_000_000)
    }

    func testDeckDetailsReplaceOnlyListedCardsInTheWindow() {
        var deck = ["a", "b", "c"].map(makeAsset(id:))
        var detailA = makeAsset(id: "a")
        detailA.assetOrigin = .camera
        var detailC = makeAsset(id: "c")
        detailC.assetOrigin = .camera
        // "b" is missing from the details (deleted elsewhere) and keeps its listing.
        SwipeSessionViewModel.apply(["a": detailA, "c": detailC], to: &deck, in: 0..<2)
        XCTAssertEqual(deck.map(\.assetOrigin), [.camera, .unknown, .unknown])
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

    func testSwipeRightKeepsSilentlyWithoutPicker() throws {
        let vm = try makeViewModel()

        vm.swipeRight()

        XCTAssertFalse(vm.showAlbumPicker, "Right-swipe must never prompt the album picker")
        XCTAssertNil(vm.pendingKeepAsset)
        XCTAssertEqual(vm.sessionStats.keptCount, 1)
        XCTAssertEqual(vm.sessionStats.organizedCount, 0)
        XCTAssertEqual(vm.currentIndex, 1, "Should advance to the next card")
        let records = try container.mainContext.fetch(FetchDescriptor<SwipeRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.assetLocalIdentifier, "asset-0")
        XCTAssertEqual(records.first?.decision, .kept)
    }

    func testKeepWithAlbumOpensPickerAndSecondRequestIsNoOp() throws {
        let vm = try makeViewModel()

        vm.keepWithAlbum()
        XCTAssertEqual(vm.pendingKeepAsset?.id, "asset-0")
        XCTAssertTrue(vm.showAlbumPicker)

        // The deck hasn't advanced, so a second request targets the same card;
        // it must not overwrite the pending keep.
        vm.keepWithAlbum()
        XCTAssertEqual(vm.pendingKeepAsset?.id, "asset-0", "A second filing request must not overwrite the pending keep")
    }

    func testUndoOfKeepRestoresStateAndRemovesRecord() async throws {
        let vm = try makeViewModel()

        vm.swipeRight()
        XCTAssertEqual(vm.sessionStats.keptCount, 1)

        await vm.undo()

        XCTAssertEqual(vm.sessionStats.keptCount, 0)
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertEqual(try swipeRecordCount(), 0, "Undo must remove the keep's SwipeRecord")
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

    /// What `PhotoLibraryService.fetchDeckListing(filter:)` returns: no resource fields.
    private func makeListing(id: String) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: .photo,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: 4032,
            pixelHeight: 3024,
            duration: 0,
            fileSize: 0,
            filename: nil,
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: false,
            isScreenshot: false,
            isLocallyAvailable: true
        )
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
