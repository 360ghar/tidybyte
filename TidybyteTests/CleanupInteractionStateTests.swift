import XCTest
@testable import Tidybyte

@MainActor
final class CleanupInteractionStateTests: XCTestCase {
    func testDuplicateSetBestMovesDeletionSelectionToPreviousBest() {
        let viewModel = DuplicateFinderViewModel()
        let first = makeAsset(id: "first")
        let second = makeAsset(id: "second")
        viewModel.exactGroups = [
            DuplicateGroup(id: "group", assets: [first, second], bestAssetId: first.id, type: .exact)
        ]
        viewModel.selectedForDeletion = [second.id]

        viewModel.setBest(assetId: second.id, in: "group")

        XCTAssertEqual(viewModel.exactGroups.first?.bestAssetId, second.id)
        XCTAssertTrue(viewModel.selectedForDeletion.contains(first.id))
        XCTAssertFalse(viewModel.selectedForDeletion.contains(second.id))
    }

    func testSimilarSetBestMovesDeletionSelectionToPreviousBest() {
        let viewModel = SimilarPhotosViewModel()
        let first = makeAsset(id: "first")
        let second = makeAsset(id: "second")
        viewModel.groups = [
            SimilarGroup(id: "group", assets: [first, second], bestAssetId: first.id)
        ]
        viewModel.selectedForDeletion = [second.id]

        viewModel.setBest(assetId: second.id, in: "group")

        XCTAssertEqual(viewModel.groups.first?.bestAssetId, second.id)
        XCTAssertTrue(viewModel.selectedForDeletion.contains(first.id))
        XCTAssertFalse(viewModel.selectedForDeletion.contains(second.id))
    }

    func testBurstSetBestMovesDeletionSelectionToPreviousBest() {
        let viewModel = BurstCleanerViewModel()
        let first = makeAsset(id: "first")
        let second = makeAsset(id: "second")
        viewModel.groups = [
            BurstGroup(id: "group", assets: [first, second], bestAssetId: first.id)
        ]
        viewModel.selectedForDeletion = [second.id]

        viewModel.setBest(assetId: second.id, in: "group")

        XCTAssertEqual(viewModel.groups.first?.bestAssetId, second.id)
        // LF-12: the old best is NOT force-inserted — an explicitly deselected
        // old best stays kept (only an explicitly armed one stays armed).
        XCTAssertFalse(viewModel.selectedForDeletion.contains(first.id))
        XCTAssertFalse(viewModel.selectedForDeletion.contains(second.id))
    }

    /// The destructive confirm must count what `deleteSelected()` removes. Both
    /// tools delete the union of every bucket's selection, so a photo selected on
    /// two tabs (it can be blurry AND dark, or a screenshot AND a document) is one
    /// deletion — summing the per-bucket counts would over-report it.
    func testBlurryDeleteCountDeduplicatesAcrossTabs() {
        let viewModel = BlurryPhotosViewModel()

        viewModel.activeTab = .blurry
        viewModel.toggleSelection("both")
        viewModel.activeTab = .tooDark
        viewModel.toggleSelection("both")
        XCTAssertEqual(viewModel.totalSelectedCount, 1, "one photo selected on two tabs is one deletion")

        viewModel.activeTab = .overexposed
        viewModel.toggleSelection("overexposed-only")
        XCTAssertEqual(viewModel.totalSelectedCount, 2)

        // Deselecting on one tab must not clear another tab's selection of the
        // same photo — so the union still holds both ids here.
        viewModel.activeTab = .blurry
        viewModel.toggleSelection("both")
        XCTAssertEqual(viewModel.totalSelectedCount, 2, "the .tooDark tab keeps its selection")

        viewModel.activeTab = .tooDark
        viewModel.toggleSelection("both")
        XCTAssertEqual(viewModel.totalSelectedCount, 1, "only the overexposed pick remains")
    }

    func testSmartCategoriesDeleteCountDeduplicatesAcrossCategories() {
        let viewModel = SmartCategoriesViewModel()

        viewModel.activeCategory = .memes
        viewModel.toggleSelection("both")
        viewModel.activeCategory = .documents
        viewModel.toggleSelection("both")
        XCTAssertEqual(viewModel.totalSelectedCount, 1, "one photo selected on two tabs is one deletion")

        viewModel.activeCategory = .pets
        viewModel.toggleSelection("pets-only")
        XCTAssertEqual(viewModel.totalSelectedCount, 2)
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
