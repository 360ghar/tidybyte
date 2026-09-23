import XCTest
import SwiftData
@testable import Tidybyte

/// E10: regression tests for the unified stats math and the crash-safety
/// journal — the two highest-risk pure-logic surfaces that the previous audit
/// claimed were covered but weren't.
@MainActor
final class MediaLibraryStatsTests: XCTestCase {

    // MARK: - Fixtures

    private func asset(
        id: String,
        mediaType: MediaType = .photo,
        size: Int64,
        isScreenshot: Bool = false,
        isLivePhoto: Bool = false,
        isFavorite: Bool = false
    ) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: mediaType,
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            duration: 0,
            fileSize: size,
            filename: nil,
            isFavorite: isFavorite,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: isLivePhoto,
            isScreenshot: isScreenshot,
            isLocallyAvailable: true
        )
    }

    private let threshold = Int64(10_000_000) // 10 MB

    // MARK: - Bucket disjointness (APP-04 invariant)

    func testBucketsAreDisjointByAsset() {
        let assets = [
            asset(id: "shot", size: 20_000_000, isScreenshot: true),        // screenshot + large
            asset(id: "live", size: 20_000_000, isLivePhoto: true),         // live + large
            asset(id: "bigvideo", mediaType: .video, size: 200_000_000),    // large video + large file
            asset(id: "big", size: 50_000_000),                             // plain large file
            asset(id: "small", size: 1_000_000)
        ]

        let buckets = ReclaimBucketer.buckets(from: assets, largeFileThresholdBytes: threshold)

        var seenIds = Set<String>()
        for bucket in buckets {
            for id in bucket.ids {
                XCTAssertFalse(seenIds.contains(id), "asset \(id) appeared in two buckets")
                seenIds.insert(id)
            }
        }
        // Every reclaimable-classified asset appears exactly once.
        XCTAssertEqual(seenIds.count, 4, "screenshot, live, big video, and big photo should each be bucketed once")
    }

    /// APP-12: the widget's toCleanCount must not double-count a screenshot
    /// that also clears the large-file threshold.
    func testLargeFileCountExcludesScreenshots() {
        let assets = [
            asset(id: "huge-shot", size: 30_000_000, isScreenshot: true),
            asset(id: "normal-shot", size: 1_000_000, isScreenshot: true),
            asset(id: "large-photo", size: 30_000_000)
        ]
        let stats = MediaLibraryStats.build(from: assets, largeFileThresholdBytes: threshold)

        XCTAssertEqual(stats.screenshotCount, 2)
        XCTAssertEqual(stats.largeFileCount, 1, "screenshots are counted separately and excluded from large files")
        XCTAssertEqual(stats.toCleanCount, 3, "widget count = all screenshots + non-screenshot large files")
    }

    /// Widget↔dashboard parity: `reclaimableBytes` equals the hand-computed sum
    /// of the dashboard's win buckets for these assets.
    ///
    /// The expected total is written out literally on purpose. Asserting
    /// `stats.reclaimableBytes == buckets(...).reduce(...)` would be
    /// self-referential — `MediaLibraryStats.build` computes the field with that
    /// exact expression — and so could never fail.
    func testReclaimableBytesMatchesBucketSum() {
        let assets = [
            asset(id: "shot", size: 20_000_000, isScreenshot: true),
            asset(id: "live", size: 20_000_000, isLivePhoto: true),
            asset(id: "bigvideo", mediaType: .video, size: 200_000_000),
            asset(id: "big", size: 50_000_000)
        ]
        let stats = MediaLibraryStats.build(from: assets, largeFileThresholdBytes: threshold)

        // screenshots 20M (full) + livePhotos 20M/2 + largeVideos 200M/2 + largeFiles 50M
        XCTAssertEqual(stats.reclaimableBytes, 180_000_000)
    }

    func testLivePhotosAndLargeVideosAreHalvedInReclaimEstimate() {
        let assets = [
            asset(id: "live", size: 20_000_000, isLivePhoto: true),
            asset(id: "bigvideo", mediaType: .video, size: 200_000_000)
        ]
        let buckets = ReclaimBucketer.buckets(from: assets, largeFileThresholdBytes: threshold)
        let byKey = Dictionary(uniqueKeysWithValues: buckets.map { ($0.key, $0) })

        XCTAssertEqual(byKey["livePhotos"]?.bytes, 10_000_000)
        XCTAssertEqual(byKey["largeVideos"]?.bytes, 100_000_000)
    }

    func testEmptyLibraryProducesZeroedStats() {
        let stats = MediaLibraryStats.build(from: [], largeFileThresholdBytes: threshold)
        XCTAssertEqual(stats.totalBytes, 0)
        XCTAssertEqual(stats.toCleanCount, 0)
        XCTAssertEqual(stats.reclaimableBytes, 0)
    }

    // MARK: - displaySize (SHARED-03/E1)

    func testDisplaySizeHandlesZeroByteAssets() {
        let unknown = asset(id: "icloud", size: 0)
        XCTAssertEqual(unknown.displaySize, "Size unavailable")

        let known = asset(id: "local", size: 5_000_000)
        XCTAssertFalse(known.displaySize.isEmpty)
        XCTAssertNotEqual(known.displaySize, "Size unavailable")
    }

    // MARK: - BestAssetSelector determinism

    func testBestAssetSelectorTiebreakIsStableAndDeterministic() {
        // Identical metadata except id → the smaller id must win, every time.
        let first = asset(id: "b", size: 1_000)
        let second = asset(id: "a", size: 1_000)
        for _ in 0..<10 {
            XCTAssertEqual(BestAssetSelector.bestByMetadata(from: [first, second])?.id, "a")
        }
    }

    func testBestAssetSelectorPrefersFavoriteAtEqualResolution() {
        // Ladder: burst pick → favorite → resolution → date → id.
        let favorite = AssetSummary(
            id: "fav", mediaType: .photo, creationDate: nil, modificationDate: nil,
            pixelWidth: 100, pixelHeight: 100, duration: 0, fileSize: 1_000,
            filename: nil, isFavorite: true, isBurst: false, burstIdentifier: nil,
            isLivePhoto: false, isScreenshot: false, isLocallyAvailable: true
        )
        let nonFavorite = asset(id: "plain", size: 1_000)
        XCTAssertEqual(BestAssetSelector.bestByMetadata(from: [favorite, nonFavorite])?.id, "fav")
    }

    func testBestAssetSelectorPrefersFavoriteOverHigherResolution() {
        // Favorite comes before resolution: deleting the favorited copy would
        // drop the user's favorite mark.
        let favorite = asset(id: "fav", size: 1_000, isFavorite: true)
        let bigger = AssetSummary(
            id: "big", mediaType: .photo, creationDate: nil, modificationDate: nil,
            pixelWidth: 800, pixelHeight: 800, duration: 0, fileSize: 9_000,
            filename: nil, isFavorite: false, isBurst: false, burstIdentifier: nil,
            isLivePhoto: false, isScreenshot: false, isLocallyAvailable: true
        )
        XCTAssertEqual(BestAssetSelector.bestByMetadata(from: [favorite, bigger])?.id, "fav")
    }

    func testBestAssetSelectorPrefersUserBurstPickThenIPhonePick() {
        var user = asset(id: "user", size: 1_000)
        user.burstPick = .user
        var auto = asset(id: "auto", size: 1_000, isFavorite: true)
        auto.burstPick = .iPhone
        let plain = asset(id: "plain", size: 1_000, isFavorite: true)
        XCTAssertEqual(BestAssetSelector.bestByMetadata(from: [plain, auto, user])?.id, "user")
        XCTAssertEqual(BestAssetSelector.bestByMetadata(from: [plain, auto])?.id, "auto")
    }

    // MARK: - Compression journal (D1)

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CompressionRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testPendingRecordNeverCountsAsSavingsOrFailure() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .video,
            assetId: "asset-1",
            originalSize: 1_000,
            compressedSize: 0,
            exportPreset: "1080p"
        )
        XCTAssertTrue(record.isPending)
        XCTAssertFalse(record.succeeded, "pending rows must not render as savings")
        XCTAssertFalse(record.isFailed)
        XCTAssertEqual(record.savedBytes, 0)
    }

    func testJournalFinalizeCompletesTheSwap() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .photo,
            assetId: "asset-2",
            originalSize: 1_000,
            compressedSize: 400,
            exportPreset: "high"
        )
        record.compressedSizeBytes = 400
        CompressionJournal.finalize(record, outcome: .completed, modelContext: context)

        XCTAssertTrue(record.succeeded)
        XCTAssertEqual(record.savedBytes, 600)
        XCTAssertNil(record.replacementAssetLocalIdentifier)
    }

    func testReconcileResolvesCompletedSwapWhenOriginalVanished() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        // A swap whose original no longer exists in PhotoKit AND whose
        // replacement was journaled (id + real compressed size, recorded at
        // save-commit time) finalizes as completed with real savings — not the
        // phantom originalSize - 0 that a 0-byte row would report.
        let record = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .video,
            assetId: "definitely-not-a-real-asset-id",
            originalSize: 1_000,
            compressedSize: 0,
            exportPreset: "720p"
        )
        CompressionJournal.recordReplacement(
            record,
            replacementId: "definitely-not-a-real-replacement-id",
            compressedSize: 400,
            modelContext: context
        )
        await CompressionJournal.reconcile(modelContext: context)

        XCTAssertEqual(record.outcome, "completed")
        XCTAssertEqual(record.savedBytes, 600, "savings must use the journaled compressed size, not 0")
    }

    /// The reconcile decision table, exercised directly: `reconcile` itself needs
    /// a live photo library for the "original still present" branches, so there
    /// the semantics are pinned here instead of going untested.
    func testReconcileResolutionDecisionTable() {
        // Original gone + replacement journaled → the swap finished.
        XCTAssertEqual(
            CompressionJournal.resolution(originalExists: false, replacementId: "r", saveAttempted: true),
            .completed
        )
        // Original gone, nothing journaled → the user deleted it outside the swap.
        XCTAssertEqual(
            CompressionJournal.resolution(originalExists: false, replacementId: nil, saveAttempted: true),
            .failed
        )
        // Both copies exist → remove the orphan.
        XCTAssertEqual(
            CompressionJournal.resolution(originalExists: true, replacementId: "r", saveAttempted: true),
            .deleteOrphanThenFail(id: "r")
        )
        // Both copies exist, per the record's own replacement id — `saveAttempted`
        // must not change that (a rollback may have cleared the id, not the flag).
        XCTAssertEqual(
            CompressionJournal.resolution(originalExists: true, replacementId: "r", saveAttempted: false),
            .deleteOrphanThenFail(id: "r")
        )
        // Original only, no library write had begun → nothing durable, drop it.
        XCTAssertEqual(
            CompressionJournal.resolution(originalExists: true, replacementId: nil, saveAttempted: false),
            .dropRow
        )
        // Original only, but the library write HAD begun → a copy may exist that
        // the journal cannot name; it must not be dropped silently.
        XCTAssertEqual(
            CompressionJournal.resolution(originalExists: true, replacementId: nil, saveAttempted: true),
            .failedWithPossibleOrphan
        )
    }

    func testMarkSaveAttemptedPersistsOnTheRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .video,
            assetId: "asset-save-attempt",
            originalSize: 1_000,
            compressedSize: 0,
            exportPreset: "720p"
        )
        XCTAssertFalse(record.saveAttempted, "a fresh pending row has not started its library write")

        CompressionJournal.markSaveAttempted(record, modelContext: context)

        // Round-trips through the store (the flag is what reconcile reads on a
        // later launch, not the in-memory record).
        let fetched = try context.fetch(FetchDescriptor<CompressionRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertTrue(fetched.first?.saveAttempted ?? false)
    }

    func testMarkPendingSkippedIsNotAFailure() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .photo,
            assetId: "asset-icloud-only",
            originalSize: 0,
            compressedSize: 0,
            exportPreset: "high"
        )

        await CompressionJournal.markPendingSkipped(assetId: "asset-icloud-only", modelContext: context)

        XCTAssertEqual(record.outcome, CompressionOutcome.skipped.rawValue)
        XCTAssertFalse(record.isPending)
        XCTAssertFalse(record.isFailed, "an intentional skip must not render a red badge")
        XCTAssertFalse(record.succeeded)
        XCTAssertEqual(record.savedBytes, 0)
    }

    func testMarkPendingSkippedIgnoresUnknownRowsAndResolvedOnes() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        // No row at all → no-op (must not insert or throw).
        await CompressionJournal.markPendingSkipped(assetId: "never-journaled", modelContext: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompressionRecord>()).isEmpty)

        // A row that already completed must not be rewritten by a late skip.
        let record = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .video,
            assetId: "already-done",
            originalSize: 1_000,
            compressedSize: 400,
            exportPreset: "480p"
        )
        CompressionJournal.finalize(record, outcome: .completed, modelContext: context)
        await CompressionJournal.markPendingSkipped(assetId: "already-done", modelContext: context)
        XCTAssertTrue(record.succeeded, "only PENDING rows are resolved")
    }

    func testReconcileFinalizesEveryPendingRowForUnknownAssets() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        // In the unit-test environment no PhotoKit assets exist, so every
        // pending row hits the "original gone" branch. With no replacement
        // journaled, "original gone" means the user deleted the asset outside
        // the swap — there is nothing to credit, so the rows finalize as
        // failed rather than lingering as pending forever (or counting phantom
        // savings). The (original present) branches require a real library
        // asset and are covered by on-device behavior.
        let first = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .video,
            assetId: "also-not-real",
            originalSize: 1_000,
            compressedSize: 0,
            exportPreset: "480p"
        )
        let second = try CompressionJournal.beginPending(
            modelContext: context,
            mediaType: .photo,
            assetId: "still-not-real",
            originalSize: 2_000,
            compressedSize: 0,
            exportPreset: "high"
        )
        await CompressionJournal.reconcile(modelContext: context)

        XCTAssertEqual(first.outcome, "failed")
        XCTAssertEqual(second.outcome, "failed")
        let pendingRemaining = try context.fetch(FetchDescriptor<CompressionRecord>(
            predicate: #Predicate { $0.outcome == "pending" }
        ))
        XCTAssertTrue(pendingRemaining.isEmpty)
    }

    // MARK: - Taxonomy normalization (C4)

    func testTaxonomyNormalizationHandlesHyphensAndSpaces() {
        XCTAssertEqual(PhotoCategorizationService.normalizeTaxonomyLabel("Baked Goods"), "baked_goods")
        XCTAssertEqual(PhotoCategorizationService.normalizeTaxonomyLabel("baked-goods"), "baked_goods")
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "baked-goods"), .food)
    }

    // MARK: - ScanState (shared location C16)

    func testScanStateEquatable() {
        XCTAssertEqual(ScanState.idle, ScanState.idle)
        XCTAssertEqual(ScanState.scanning(0.5), ScanState.scanning(0.5))
        XCTAssertNotEqual(ScanState.idle, ScanState.completed)
    }
}
