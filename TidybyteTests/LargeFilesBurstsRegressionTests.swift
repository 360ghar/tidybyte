import XCTest
@testable import Tidybyte

/// Regression tests for the Large Files & Bursts audit fixes
/// (LF-01, LF-02, LF-05, LF-07, LF-09, LF-10, LF-12, LF-13).
@MainActor
final class LargeFilesBurstsRegressionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppPreferences.saveLargeFileThresholdMB(10)
    }

    // MARK: - LF-01 / LF-02: selection preservation across refresh & delete

    func testMergedSelectionPreservesUserDeselections() {
        let group = makeGroup(id: "g1", best: "a", others: ["b", "c"])
        // The user explicitly deselected "b" (kept it); only "c" is armed.
        let merged = BurstCleanerViewModel.mergedSelection(
            oldSelection: ["c"],
            survivingIds: ["a", "b", "c"],
            touchedGroups: ["g1"],
            groups: [group]
        )
        XCTAssertEqual(merged, ["c"], "touched groups must keep exactly the user's surviving picks")
    }

    func testMergedSelectionDropsDeletedIdsAndRearmsUntouchedGroups() {
        let touched = makeGroup(id: "touched", best: "a", others: ["b", "c"])
        let untouched = makeGroup(id: "fresh", best: "x", others: ["y", "z"])
        let merged = BurstCleanerViewModel.mergedSelection(
            oldSelection: ["b", "y", "gone"], // "gone" no longer exists
            survivingIds: ["a", "b", "c", "x", "y", "z"],
            touchedGroups: ["touched"],
            groups: [touched, untouched]
        )
        // Touched group: only the user's surviving pick. Untouched group:
        // all non-best frames re-armed.
        XCTAssertEqual(merged, ["b", "y", "z"])
    }

    func testMergedSelectionExcludesBestFrame() {
        let group = makeGroup(id: "g1", best: "a", others: ["b", "c"])
        let merged = BurstCleanerViewModel.mergedSelection(
            oldSelection: ["b"],
            survivingIds: ["a", "b", "c"],
            touchedGroups: [],
            groups: [group]
        )
        XCTAssertEqual(merged, ["b", "c"], "untouched groups arm all non-best frames, never the best")
    }

    func testRefreshKeepsManuallySetBestWhenFrameStillExists() {
        let oldGroups = [makeGroup(id: "g1", best: "a", others: ["b", "c"])]
        // The library changed and the computed best is now "b".
        let newGroups = [makeGroup(id: "g1", best: "b", others: ["a", "c"])]
        let preserved = BurstCleanerViewModel.preservingManualBests(
            in: newGroups,
            oldGroups: oldGroups,
            manuallySetBest: ["g1"]
        )
        XCTAssertEqual(preserved.first?.bestAssetId, "a")
    }

    func testRefreshFallsBackToComputedBestWhenManualBestVanished() {
        let oldGroups = [makeGroup(id: "g1", best: "a", others: ["b", "c"])]
        // "a" was deleted elsewhere; the refreshed group recomputes best = "b".
        let newGroups = [makeGroup(id: "g1", best: "b", others: ["c"])]
        let preserved = BurstCleanerViewModel.preservingManualBests(
            in: newGroups,
            oldGroups: oldGroups,
            manuallySetBest: ["g1"]
        )
        XCTAssertEqual(preserved.first?.bestAssetId, "b")
    }

    func testRefreshDoesNotTouchDefaultBests() {
        let oldGroups = [makeGroup(id: "g1", best: "a", others: ["b", "c"])]
        let newGroups = [makeGroup(id: "g1", best: "b", others: ["a", "c"])]
        let preserved = BurstCleanerViewModel.preservingManualBests(
            in: newGroups,
            oldGroups: oldGroups,
            manuallySetBest: [] // user never picked a best
        )
        XCTAssertEqual(preserved.first?.bestAssetId, "b", "default bests recompute on refresh")
    }

    // MARK: - LF-12: setBest preserves explicit deselection of the old best

    func testSetBestDoesNotForceInsertDeselectedOldBest() {
        let viewModel = BurstCleanerViewModel()
        let a = makeAsset(id: "a", fileSize: 8_000_000, filename: "a.jpg")
        let b = makeAsset(id: "b", fileSize: 9_000_000, filename: "b.jpg")
        viewModel.groups = [BurstGroup(id: "g1", assets: [a, b], bestAssetId: a.id)]
        viewModel.selectedForDeletion = [b.id] // user deselected "b" (kept it)

        viewModel.setBest(assetId: b.id, in: "g1")

        XCTAssertEqual(viewModel.groups.first?.bestAssetId, b.id)
        XCTAssertTrue(
            viewModel.selectedForDeletion.isEmpty,
            "the deselected old best must not be force-re-armed (LF-12)"
        )
        XCTAssertFalse(viewModel.selectedForDeletion.contains(b.id))
        XCTAssertEqual(viewModel.manuallySetBest, ["g1"])
        XCTAssertEqual(viewModel.touchedGroups, ["g1"])
    }

    func testSetBestKeepsExplicitlyArmedOldBestInDeletionSet() {
        let viewModel = BurstCleanerViewModel()
        let a = makeAsset(id: "a", fileSize: 8_000_000, filename: "a.jpg")
        let b = makeAsset(id: "b", fileSize: 9_000_000, filename: "b.jpg")
        viewModel.groups = [BurstGroup(id: "g1", assets: [a, b], bestAssetId: a.id)]
        viewModel.selectedForDeletion = [a.id] // user explicitly armed the best

        viewModel.setBest(assetId: b.id, in: "g1")

        XCTAssertEqual(viewModel.groups.first?.bestAssetId, b.id)
        XCTAssertEqual(
            viewModel.selectedForDeletion,
            [a.id],
            "an explicitly armed old best stays armed as a non-best frame"
        )
        XCTAssertFalse(viewModel.selectedForDeletion.contains(b.id))
    }

    // MARK: - LF-05: threshold label math (decimal MB -> binary file size)

    func testThresholdLabelUsesBinaryDisplayConsistentWithRows() {
        // The label is built through LargeFilesViewModel.minSizeLabel, which
        // uses the SAME byte formatter as the list rows, so the stated minimum
        // always matches how a threshold-sized file renders. (ByteCountFormatter
        // `.file` is decimal — 10,000,000 B renders "10 MB" — so the pre-fix
        // "decimal label vs binary row" mismatch was a phantom; the real win is
        // the single shared code path that makes drift impossible.)
        XCTAssertEqual(Int64(10 * 1_000_000), 10_000_000, "10 MB (decimal) must map to 10,000,000 bytes")
        let label = LargeFilesViewModel.minSizeLabel(thresholdMB: 10)
        XCTAssertEqual(label, "Min size: \(Int64(10_000_000).formattedFileSize)")
    }

    func testThresholdBytesFollowsPersistedPreference() {
        AppPreferences.saveLargeFileThresholdMB(75)
        let viewModel = LargeFilesViewModel()
        XCTAssertEqual(viewModel.thresholdMB, 75)
        XCTAssertEqual(viewModel.thresholdBytes, 75_000_000)
    }

    // MARK: - LF-07: filteredAssets recomputes per mutation with correct ordering

    func testFilteredAssetsFollowsSortAndFilterMutations() {
        let viewModel = LargeFilesViewModel()
        viewModel.assets = [
            makeAsset(id: "b", mediaType: .photo, fileSize: 25_000_000, filename: "b.jpg"),
            makeAsset(id: "a", mediaType: .photo, fileSize: 15_000_000, filename: "a.jpg"),
            makeAsset(id: "c", mediaType: .video, fileSize: 30_000_000, filename: "c.mov")
        ]

        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["c", "b", "a"], "default sort is largest-first")

        viewModel.sortOrder = .filename
        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["a", "b", "c"])

        viewModel.mediaFilter = .videos
        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["c"])

        // Threshold change must invalidate the cache (LF-06 backing).
        AppPreferences.saveLargeFileThresholdMB(40)
        XCTAssertTrue(viewModel.filteredAssets.isEmpty, "raising the threshold must re-filter")
    }

    func testFilteredAssetsExcludesBelowThresholdAndUnknownSize() {
        let viewModel = LargeFilesViewModel()
        viewModel.assets = [
            makeAsset(id: "big", mediaType: .photo, fileSize: 50_000_000, filename: "big.jpg"),
            makeAsset(id: "small", mediaType: .photo, fileSize: 4_000_000, filename: "small.jpg"),
            makeAsset(id: "unknown", mediaType: .photo, fileSize: 0, filename: "unknown.jpg")
        ]
        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["big"])
    }

    // MARK: - LF-10: unknown-size count surfaced

    func testZeroSizeAssetsAreCountedAndExcluded() {
        let viewModel = LargeFilesViewModel()
        viewModel.assets = [
            makeAsset(id: "huge-unknown", mediaType: .video, fileSize: 0, filename: "huge.mov"),
            makeAsset(id: "known", mediaType: .photo, fileSize: 50_000_000, filename: "known.jpg")
        ]
        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["known"])
        XCTAssertEqual(viewModel.zeroSizeCount, 1)
    }

    func testZeroSizeCountResetsWhenAssetsChange() {
        let viewModel = LargeFilesViewModel()
        viewModel.assets = [
            makeAsset(id: "unknown", mediaType: .photo, fileSize: 0, filename: "unknown.jpg")
        ]
        XCTAssertEqual(viewModel.zeroSizeCount, 1)
        viewModel.assets = [
            makeAsset(id: "known", mediaType: .photo, fileSize: 50_000_000, filename: "known.jpg")
        ]
        XCTAssertEqual(viewModel.zeroSizeCount, 0)
    }

    // MARK: - LF-09: temp export folder cleanup

    func testRemoveExportFolderIsIdempotent() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestShareExport-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("media.jpg")
        try? Data("x".utf8).write(to: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        LargeFilesViewModel.removeExportFolder(at: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))

        // Deleting an already-deleted folder must not crash (LF-09).
        LargeFilesViewModel.removeExportFolder(at: folder)
    }

    func testOrphanSweepRemovesOnlyShareExportFolders() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SweepTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let orphan = directory.appendingPathComponent("ShareExport-abc", isDirectory: true)
        let unrelated = directory.appendingPathComponent("KeepMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        LargeFilesViewModel.removeOrphanedShareExportFolders(in: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    // MARK: - LF-13: empty burst bins are skipped

    func testRebuildGroupsSkipsEmptyBurstBins() {
        let rebuilt = BurstCleanerViewModel.rebuildGroups(from: [:])
        XCTAssertTrue(rebuilt.isEmpty)
    }

    func testRebuildGroupsSortsByCountAndPicksBest() {
        let twoFrame = BurstCleanerViewModel.rebuildGroups(from: [
            "burst-2": [
                makeAsset(id: "2a", fileSize: 8_000_000, filename: "2a.jpg", pixelWidth: 3000, pixelHeight: 2000),
                makeAsset(id: "2b", fileSize: 9_000_000, filename: "2b.jpg", pixelWidth: 4032, pixelHeight: 3024)
            ]
        ])
        XCTAssertEqual(twoFrame.count, 1)
        // No favorites: highest resolution wins.
        XCTAssertEqual(twoFrame.first?.bestAssetId, "2b")
        XCTAssertEqual(twoFrame.first?.assets.count, 2)
    }

    // MARK: - Auto-Clean honors per-group curation (PR #2 finding 1)

    func testAutoCleanArmedIdsArmSuggestionsForUntouchedGroups() {
        let group = makeGroup(id: "g1", best: "a", others: ["b", "c"])
        let armed = BurstCleanerViewModel.autoCleanArmedIds(
            groups: [group],
            touchedGroups: [],
            selection: []
        )
        XCTAssertEqual(armed, ["b", "c"])
    }

    func testAutoCleanArmedIdsKeepUserDeselectionsInTouchedGroups() {
        let group = makeGroup(id: "g1", best: "a", others: ["b", "c"])
        // The user touched the group and kept "b": only "c" stays armed.
        let armed = BurstCleanerViewModel.autoCleanArmedIds(
            groups: [group],
            touchedGroups: ["g1"],
            selection: ["c"]
        )
        XCTAssertEqual(armed, ["c"], "a deselected frame must not be re-armed by Auto-Clean")
    }

    func testAutoCleanArmedIdsMixTouchedAndUntouchedGroups() {
        let touched = makeGroup(id: "touched", best: "a", others: ["b", "c"])
        let fresh = makeGroup(id: "fresh", best: "x", others: ["y", "z"])
        let armed = BurstCleanerViewModel.autoCleanArmedIds(
            groups: [touched, fresh],
            touchedGroups: ["touched"],
            selection: ["b"]
        )
        XCTAssertEqual(armed, ["b", "y", "z"])
    }

    // MARK: - Auto-Clean's confirm count matches what it deletes (PR #2 finding)

    /// The confirm button and its enable check used the suggestion set for every
    /// group, while the delete arms the user's surviving picks for a touched
    /// group — so the alert over-counted and the button could stay live for a
    /// zero-delete no-op.
    func testAutoCleanArmedCountTracksTheDeleteNotTheSuggestionSummary() {
        let viewModel = BurstCleanerViewModel()
        viewModel.groups = [makeGroup(id: "g1", best: "a", others: ["b", "c"])]
        // Untouched group: the two sets agree.
        XCTAssertEqual(viewModel.deletableCount, 2)
        XCTAssertEqual(viewModel.autoCleanArmedCount, 2)

        // The user touches the group and keeps "b": Auto-Clean now arms only
        // "c", while the passive "N removable" summary still describes the
        // untouched suggestion set.
        viewModel.toggleSelection("c")
        XCTAssertEqual(viewModel.deletableCount, 2, "the suggestion summary is not the armed set")
        XCTAssertEqual(
            viewModel.autoCleanArmedCount, 1,
            "the confirm count must match the set Auto-Clean really deletes"
        )
    }

    /// Touching a group and then clearing it leaves the armed set empty while the
    /// suggestion summary still reports two frames.
    func testAutoCleanArmedCountIsZeroAfterClearingATouchedGroup() {
        let viewModel = BurstCleanerViewModel()
        viewModel.groups = [makeGroup(id: "g1", best: "a", others: ["b", "c"])]
        viewModel.deselectAll()
        XCTAssertEqual(viewModel.deletableCount, 2)
        XCTAssertEqual(
            viewModel.autoCleanArmedCount, 0,
            "Auto-Clean must be disabled when it would delete nothing"
        )
    }

    /// The confirm copy promises "Favorites are kept". Auto-Clean never suggests
    /// a favorite, but Select All is an explicit choice that arms one.
    func testAutoCleanArmedIncludesFavoriteOnlyAfterAnExplicitPick() {
        let viewModel = BurstCleanerViewModel()
        viewModel.groups = [makeGroup(id: "g1", best: "a", others: ["b", "c"], favorites: ["c"])]
        XCTAssertFalse(
            viewModel.autoCleanArmedIncludesFavorite,
            "an untouched group never arms a favorite"
        )

        viewModel.selectAllNonBest()
        XCTAssertTrue(
            viewModel.autoCleanArmedIncludesFavorite,
            "the confirm must stop promising favorites are kept once one is armed"
        )
    }

    // MARK: - Helpers

    private func makeGroup(
        id: String,
        best: String,
        others: [String],
        favorites: Set<String> = []
    ) -> BurstGroup {
        func asset(_ assetId: String, fileSize: Int64) -> AssetSummary {
            makeAsset(
                id: assetId,
                fileSize: fileSize,
                filename: "\(assetId).jpg",
                isFavorite: favorites.contains(assetId)
            )
        }
        return BurstGroup(
            id: id,
            assets: [asset(best, fileSize: 9_000_000)] + others.map { asset($0, fileSize: 8_000_000) },
            bestAssetId: best
        )
    }

    private func makeAsset(
        id: String,
        mediaType: MediaType = .photo,
        fileSize: Int64,
        filename: String,
        pixelWidth: Int = 4032,
        pixelHeight: Int = 3024,
        isFavorite: Bool = false
    ) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: mediaType,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: mediaType == .video ? 60 : 0,
            fileSize: fileSize,
            filename: filename,
            isFavorite: isFavorite,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: false,
            isScreenshot: false,
            isLocallyAvailable: true
        )
    }
}
