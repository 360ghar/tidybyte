import XCTest
@testable import Tidybyte

/// Pins the cleanup home's grouping and the hero's byte math.
///
/// The byte rule is the part worth testing: the hero sums two sets that must stay
/// disjoint, and the obvious implementation (sum screenshots, then sum everything
/// over the threshold) double counts every large screenshot.
final class CleanupHomeGroupingTests: XCTestCase {

    // MARK: - Category grouping

    func testEveryToolBelongsToExactlyOneCategory() {
        let grouped = CleanupToolCategory.allCases.flatMap(\.tools)
        XCTAssertEqual(
            Set(grouped), Set(CleanupTool.allCases),
            "every tool must appear in a section"
        )
        XCTAssertEqual(
            grouped.count, CleanupTool.allCases.count,
            "no tool may appear in two sections"
        )
    }

    func testCategoryOrderIsStableAndComplete() {
        XCTAssertEqual(CleanupToolCategory.allCases, [.freeUpSpace, .organize, .shrink])
    }

    func testCategoriesHaveTitlesAndSubtitles() {
        for category in CleanupToolCategory.allCases {
            XCTAssertFalse(category.title.isEmpty, "\(category) needs a title")
            XCTAssertFalse(category.subtitle.isEmpty, "\(category) needs a subtitle")
        }
    }

    func testDeletingToolsAreGroupedAsFreeUpSpace() {
        for tool in [CleanupTool.duplicates, .similar, .blurry, .largeFiles, .bursts] {
            XCTAssertEqual(tool.category, .freeUpSpace, "\(tool) deletes, so it frees space")
        }
    }

    func testConversionToolsAreNotGroupedAsFreeUpSpace() {
        // These never delete the original without converting it first, so putting
        // them under "Free Up Space" would misdescribe them.
        for tool in [CleanupTool.livePhotos, .videoCompression, .photoCompression] {
            XCTAssertEqual(tool.category, .shrink, "\(tool) converts rather than deletes")
        }
    }

    func testReviewToolsAreGroupedAsOrganize() {
        for tool in [CleanupTool.screenshots, .smartCategories] {
            XCTAssertEqual(tool.category, .organize, "\(tool) is a review tool")
        }
    }

    // MARK: - Roll-up counts

    func testRollupCountsEachCategory() {
        let assets = [
            asset(size: 1_000, screenshot: true),
            asset(size: 2_000, live: true),
            asset(size: 3_000, type: .video),
            asset(size: 4_000),
            asset(size: 5_000)
        ]

        let rollup = CleanupLibraryRollup.compute(from: assets, thresholdBytes: 100_000)

        XCTAssertEqual(rollup.screenshots, 1)
        XCTAssertEqual(rollup.livePhotos, 1)
        XCTAssertEqual(rollup.videos, 1)
        // Screenshots count here too: a screenshot is a photo and Photo
        // Compression can re-encode it, so it is intentionally in both the
        // Screenshots and Photo Compression badges. Only live photos are
        // excluded (they are handled by the Live Photos tool instead).
        XCTAssertEqual(rollup.compressiblePhotos, 3)
        XCTAssertEqual(rollup.largeFiles, 0)
    }

    func testReclaimableTotalExcludesSmallAndLiveAssets() {
        let assets = [
            asset(size: 500, screenshot: true),
            asset(size: 9_000, live: true),
            asset(size: 4_000, type: .video)
        ]

        let rollup = CleanupLibraryRollup.compute(from: assets, thresholdBytes: 100_000)

        // Only the screenshot is outright deletable at this threshold.
        XCTAssertEqual(rollup.reclaimableBytes, 500)
        XCTAssertEqual(rollup.reclaimableItemCount, 1)
    }

    /// The regression this whole roll-up exists to prevent.
    func testLargeScreenshotIsCountedOnceNotTwice() {
        let screenshotSize: Int64 = 50_000
        let assets = [
            asset(size: screenshotSize, screenshot: true),
            asset(size: 30_000, type: .video)
        ]

        let rollup = CleanupLibraryRollup.compute(from: assets, thresholdBytes: 10_000)

        // Both are over the threshold, but the screenshot must not be added a
        // second time by the large-file branch.
        XCTAssertEqual(rollup.reclaimableBytes, screenshotSize + 30_000)
        XCTAssertEqual(rollup.reclaimableItemCount, 2)
    }

    func testLargeFilesBadgeStillCountsLargeScreenshots() {
        // The badge answers "how many files are over the threshold", which is a
        // different question from the hero's disjoint total — a large screenshot
        // belongs in both.
        let assets = [
            asset(size: 50_000, screenshot: true),
            asset(size: 60_000)
        ]

        let rollup = CleanupLibraryRollup.compute(from: assets, thresholdBytes: 10_000)

        XCTAssertEqual(rollup.largeFiles, 2)
        XCTAssertEqual(rollup.reclaimableBytes, 110_000)
    }

    func testThresholdIsInclusive() {
        let exactly: Int64 = 10_000
        let rollup = CleanupLibraryRollup.compute(
            from: [asset(size: exactly)],
            thresholdBytes: exactly
        )
        XCTAssertEqual(rollup.largeFiles, 1, "a file exactly at the threshold counts as large")
        XCTAssertEqual(rollup.reclaimableBytes, exactly)
    }

    func testUnknownSizeAssetsContributeNothingToTheHero() {
        // iCloud-only assets report 0 bytes; they must still be counted as
        // screenshots without inflating the byte total with a fake number.
        let assets = [asset(size: 0, screenshot: true), asset(size: 0, type: .video)]

        let rollup = CleanupLibraryRollup.compute(from: assets, thresholdBytes: 10_000)

        XCTAssertEqual(rollup.screenshots, 1)
        XCTAssertEqual(rollup.videos, 1)
        XCTAssertEqual(rollup.reclaimableBytes, 0)
    }

    func testEmptyLibraryProducesZeroRollup() {
        let rollup = CleanupLibraryRollup.compute(from: [], thresholdBytes: 10_000)
        XCTAssertEqual(rollup, CleanupLibraryRollup())
    }

    // MARK: - Fixtures

    private func asset(
        size: Int64 = 0,
        screenshot: Bool = false,
        live: Bool = false,
        type: MediaType = .photo
    ) -> AssetSummary {
        AssetSummary(
            id: UUID().uuidString,
            mediaType: type,
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            duration: 0,
            fileSize: size,
            filename: nil,
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: live,
            isScreenshot: screenshot,
            isLocallyAvailable: true
        )
    }
}
