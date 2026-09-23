import XCTest
@testable import Tidybyte

@MainActor
final class LargeFilesViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppPreferences.saveLargeFileThresholdMB(10)
    }

    func testFilterChangeKeepsHiddenSelection() {
        let viewModel = LargeFilesViewModel()
        viewModel.assets = [
            makeAsset(id: "video-large", mediaType: .video, fileSize: 150_000_000, filename: "video-large.mov"),
            makeAsset(id: "photo-large", mediaType: .photo, fileSize: 120_000_000, filename: "photo-large.jpg"),
            makeAsset(id: "photo-small", mediaType: .photo, fileSize: 4_000_000, filename: "photo-small.jpg")
        ]
        viewModel.selectedIds = ["video-large", "photo-large"]
        viewModel.mediaFilter = .photos

        // The video pick survives; only the visible pick counts for delete.
        XCTAssertEqual(viewModel.selectedIds, ["video-large", "photo-large"])
        XCTAssertEqual(viewModel.selectedVisibleCount, 1)
    }

    func testSelectAllUsesOnlyCurrentlyVisibleAssets() {
        let viewModel = LargeFilesViewModel()
        viewModel.assets = [
            makeAsset(id: "b", mediaType: .photo, fileSize: 25_000_000, filename: "b.jpg"),
            makeAsset(id: "a", mediaType: .photo, fileSize: 25_000_000, filename: "a.jpg"),
            makeAsset(id: "video", mediaType: .video, fileSize: 25_000_000, filename: "video.mov")
        ]
        viewModel.mediaFilter = .photos
        viewModel.sortOrder = .filename

        viewModel.selectAll()

        XCTAssertEqual(viewModel.selectedIds, ["a", "b"])
        XCTAssertEqual(viewModel.selectedVisibleCount, 2)
    }

    func testThresholdMBInitializesFromPersistedValue() {
        AppPreferences.saveLargeFileThresholdMB(75)

        let viewModel = LargeFilesViewModel()

        XCTAssertEqual(viewModel.thresholdMB, 75)
    }

    func testThresholdMBSetPersistsToDefaults() {
        let viewModel = LargeFilesViewModel()

        viewModel.thresholdMB = 123

        XCTAssertEqual(AppPreferences.largeFileThresholdMB(), 123)
    }

    private func makeAsset(id: String, mediaType: MediaType, fileSize: Int64, filename: String) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: mediaType,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: 4000,
            pixelHeight: 3000,
            duration: mediaType == .video ? 60 : 0,
            fileSize: fileSize,
            filename: filename,
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: false,
            isScreenshot: false,
            isLocallyAvailable: true
        )
    }
}
