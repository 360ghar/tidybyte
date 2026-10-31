import XCTest
@testable import Tidybyte

@MainActor
final class CleanupInteractionStateTests: XCTestCase {
    /// `ScanResults` is process-wide static state: reset it per test so
    /// hardcoded generations can't leak from one test into the next and make
    /// results depend on execution order.
    override func setUp() {
        super.setUp()
        ScanResults.resetForTesting()
    }
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

    /// One selection per photo, shared by all tabs: the bar, the confirm and
    /// the delete count the same set, and a photo in two buckets carries one
    /// check. Switching tabs keeps every pick.
    func testBlurrySelectionIsPerPhotoAcrossTabs() {
        let viewModel = BlurryPhotosViewModel()

        viewModel.activeTab = .blurry
        viewModel.toggleSelection("both")
        viewModel.activeTab = .tooDark
        XCTAssertTrue(viewModel.selectedIds.contains("both"), "the same photo shows as selected on the other tab")
        XCTAssertEqual(viewModel.totalSelectedCount, 1)

        viewModel.activeTab = .overexposed
        viewModel.toggleSelection("overexposed-only")
        XCTAssertEqual(viewModel.totalSelectedCount, 2)

        // Deselecting on any tab deselects the photo everywhere.
        viewModel.activeTab = .blurry
        viewModel.toggleSelection("both")
        XCTAssertEqual(viewModel.totalSelectedCount, 1, "only the overexposed pick remains")
    }

    func testSmartCategoriesSelectionIsPerPhotoAcrossCategories() {
        let viewModel = SmartCategoriesViewModel()

        viewModel.activeCategory = .memes
        viewModel.toggleSelection("both")
        viewModel.activeCategory = .documents
        XCTAssertTrue(viewModel.selectedIds.contains("both"))
        XCTAssertEqual(viewModel.totalSelectedCount, 1)

        viewModel.activeCategory = .pets
        viewModel.toggleSelection("pets-only")
        XCTAssertEqual(viewModel.totalSelectedCount, 2)
    }

    // MARK: - Scan results are tied to a library generation (PR #2 finding)

    /// A scan that starts before a library change and finishes after it used to
    /// republish its pre-change count, so the home badge advertised results that
    /// no longer existed.
    func testScanResultRecordedBeforeALibraryChangeIsNotPublished() {
        let staleEpoch = ScanResults.epoch
        // The library changed: cached counts expire and a new epoch starts.
        ScanResults.invalidate()
        XCTAssertNil(ScanResults.counts[.blurry], "invalidate must expire the cached count")

        // The pre-change scan finishes late: its count is dropped.
        ScanResults.record(.blurry, count: 12, epoch: staleEpoch)
        XCTAssertNil(ScanResults.counts[.blurry], "a pre-change scan must not republish")

        // A scan that started after the change publishes normally.
        ScanResults.record(.blurry, count: 7, epoch: ScanResults.epoch)
        XCTAssertEqual(ScanResults.counts[.blurry], 7)
    }

    /// A prune or delete re-derives its count from the CURRENT list, so it is
    /// accepted without an epoch — only a finished scan can be stale.
    func testDerivedRecordIsAcceptedAfterALibraryChange() {
        ScanResults.record(.screenshots, count: 3)
        ScanResults.invalidate()
        ScanResults.record(.screenshots, count: 2)
        XCTAssertEqual(ScanResults.counts[.screenshots], 2)
    }

    // MARK: - The change itself owns invalidation (PR #2 finding)

    /// The epoch advances from the library-change path, exactly once per
    /// generation. A screen can no longer clear counts on its first load — a
    /// recreated home view model used to wipe counts that were still valid.
    /// Finished scans expire on change; counts derived from the current list
    /// (a tool's own delete or prune) survive it.
    func testLibraryChangedAdvancesTheEpochOncePerGeneration() {
        ScanResults.record(.screenshots, count: 3, epoch: ScanResults.epoch)

        let generation = 70_001
        ScanResults.libraryChanged(to: generation)
        XCTAssertNil(ScanResults.counts[.screenshots], "a finished scan expires on change")

        // Re-observing the same generation advances nothing: a scan published
        // now stays visible.
        ScanResults.record(.screenshots, count: 3, epoch: ScanResults.epoch)
        ScanResults.libraryChanged(to: generation)
        XCTAssertEqual(ScanResults.counts[.screenshots], 3)

        // A genuinely new generation expires the scan again...
        ScanResults.libraryChanged(to: generation + 1)
        XCTAssertNil(ScanResults.counts[.screenshots])

        // ...while a count derived from the current list survives it.
        ScanResults.record(.screenshots, count: 2)
        ScanResults.libraryChanged(to: generation + 2)
        XCTAssertEqual(
            ScanResults.counts[.screenshots], 2,
            "a tool's own post-delete count survives the change its delete triggered"
        )
    }

    /// A scan that started before the change and finished after it is dropped,
    /// while a count derived from the current list — a tool's own delete or
    /// prune — survives it.
    func testCountDerivedAfterTheChangeSurvivesLibraryChanged() {
        let staleEpoch = ScanResults.epoch
        ScanResults.libraryChanged(to: 70_002)
        ScanResults.record(.blurry, count: 12, epoch: staleEpoch)
        XCTAssertNil(ScanResults.counts[.blurry], "a pre-change scan must not republish")

        ScanResults.record(.blurry, count: 7)
        XCTAssertEqual(ScanResults.counts[.blurry], 7)
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
