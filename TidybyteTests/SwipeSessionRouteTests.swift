import XCTest
import SwiftData
@testable import Tidybyte

final class SwipeSessionRouteTests: XCTestCase {
    func testSameFilterCreatesDistinctRoutes() {
        let first = SwipeSessionRoute(filter: .allMedia)
        let second = SwipeSessionRoute(filter: .allMedia)

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.filter, second.filter)
    }

    @MainActor
    func testResetForNewSessionClearsInProgressState() throws {
        let schema = Schema([
            SwipeRecord.self,
            CompressionRecord.self,
            StorageSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let viewModel = SwipeSessionViewModel(
            filter: .allMedia,
            photoService: PhotoLibraryService(),
            modelContext: container.mainContext
        )

        viewModel.assets = [makeAsset(id: "asset-1")]
        viewModel.showCompletion = true
        viewModel.showAlbumPicker = true
        viewModel.pendingKeepAsset = viewModel.assets.first
        viewModel.errorMessage = "Example"
        viewModel.allPhotosAlreadySwiped = true
        viewModel.isPerformingMutation = true
        viewModel.sessionStats.deletedCount = 2
        viewModel.pendingDeletionIds = ["asset-1"]
        viewModel.pendingDeletionBytes = 12_000_000
        viewModel.isDeletingBatch = true
        viewModel.deletionCommitted = true
        viewModel.skip()

        viewModel.resetForNewSession()

        XCTAssertTrue(viewModel.assets.isEmpty)
        XCTAssertEqual(viewModel.currentIndex, 0)
        XCTAssertEqual(viewModel.sessionStats.totalReviewed, 0)
        XCTAssertFalse(viewModel.showCompletion)
        XCTAssertFalse(viewModel.showAlbumPicker)
        XCTAssertNil(viewModel.pendingKeepAsset)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.allPhotosAlreadySwiped)
        XCTAssertFalse(viewModel.isPerformingMutation)
        XCTAssertFalse(viewModel.hasLoadedInitialAssets)
        XCTAssertTrue(viewModel.undoStack.isEmpty)
        XCTAssertTrue(viewModel.pendingDeletionIds.isEmpty)
        XCTAssertEqual(viewModel.pendingDeletionBytes, 0)
        XCTAssertFalse(viewModel.isDeletingBatch)
        XCTAssertFalse(viewModel.deletionCommitted)
    }

    @MainActor
    func testSwipeLeftDefersDeletion() throws {
        let container = try makeContainer()
        let viewModel = SwipeSessionViewModel(
            filter: .allMedia,
            photoService: PhotoLibraryService(),
            modelContext: container.mainContext
        )
        viewModel.assets = [makeAsset(id: "asset-1"), makeAsset(id: "asset-2")]

        viewModel.swipeLeft()

        XCTAssertEqual(viewModel.pendingDeletionIds, ["asset-1"])
        XCTAssertEqual(viewModel.pendingDeletionBytes, 12_000_000)
        XCTAssertEqual(viewModel.sessionStats.deletedCount, 1)
        XCTAssertEqual(viewModel.sessionStats.deletedBytes, 12_000_000)
        XCTAssertEqual(viewModel.currentIndex, 1)
        XCTAssertEqual(viewModel.undoStack.count, 1)
        XCTAssertEqual(viewModel.undoStack.last?.decision, .deleted)
    }

    @MainActor
    func testUndoDeleteRemovesFromPendingList() async throws {
        let container = try makeContainer()
        let viewModel = SwipeSessionViewModel(
            filter: .allMedia,
            photoService: PhotoLibraryService(),
            modelContext: container.mainContext
        )
        viewModel.assets = [makeAsset(id: "asset-1"), makeAsset(id: "asset-2")]

        viewModel.swipeLeft()
        XCTAssertEqual(viewModel.pendingDeletionIds.count, 1)

        await viewModel.undo()

        XCTAssertTrue(viewModel.pendingDeletionIds.isEmpty)
        XCTAssertEqual(viewModel.pendingDeletionBytes, 0)
        XCTAssertEqual(viewModel.sessionStats.deletedCount, 0)
        XCTAssertEqual(viewModel.sessionStats.deletedBytes, 0)
        XCTAssertEqual(viewModel.currentIndex, 0)
        XCTAssertTrue(viewModel.undoStack.isEmpty)
    }

    @MainActor
    func testMultipleSwipeLeftsAccumulatePendingDeletions() throws {
        let container = try makeContainer()
        let viewModel = SwipeSessionViewModel(
            filter: .allMedia,
            photoService: PhotoLibraryService(),
            modelContext: container.mainContext
        )
        viewModel.assets = [
            makeAsset(id: "asset-1"),
            makeAsset(id: "asset-2"),
            makeAsset(id: "asset-3")
        ]

        viewModel.swipeLeft()
        viewModel.swipeLeft()

        XCTAssertEqual(viewModel.pendingDeletionIds, ["asset-1", "asset-2"])
        XCTAssertEqual(viewModel.pendingDeletionBytes, 24_000_000)
        XCTAssertEqual(viewModel.sessionStats.deletedCount, 2)
        XCTAssertEqual(viewModel.currentIndex, 2)
        XCTAssertEqual(viewModel.undoStack.count, 2)
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SwipeRecord.self,
            CompressionRecord.self,
            StorageSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeAsset(id: String) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: .photo,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: 4000,
            pixelHeight: 3000,
            duration: 0,
            fileSize: 12_000_000,
            filename: "sample.jpg",
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: false,
            isScreenshot: false,
            isLocallyAvailable: true
        )
    }
}
