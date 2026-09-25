import Photos
import SwiftData
import XCTest
@testable import Tidybyte

@MainActor
final class CompressionRegressionTests: XCTestCase {

    /// Held for the lifetime of the test so the in-memory store (and the
    /// container's mainContext) stays valid.
    private var container: ModelContainer!

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeAsset(
        id: String,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64 = 100_000_000
    ) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: .video,
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: 10,
            fileSize: fileSize,
            filename: nil,
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: false,
            isScreenshot: false,
            isLocallyAvailable: true
        )
    }

    // MARK: - One delete prompt per batch

    func testPartitionCommitsItemsWhoseOriginalIsGone() {
        let split = OriginalsCommit.partition(["a", "b", "c"], id: { $0 }, stillPresent: ["b"])
        XCTAssertEqual(split.committed, ["a", "c"])
        XCTAssertEqual(split.kept, ["b"])
    }

    func testPartitionKeepsEverythingWhenUserDeclines() {
        let split = OriginalsCommit.partition(["a", "b"], id: { $0 }, stillPresent: ["a", "b"])
        XCTAssertTrue(split.committed.isEmpty)
        XCTAssertEqual(split.kept, ["a", "b"])
    }

    /// Reconcile must not touch a row whose swap is still waiting for the
    /// Originals Kept choice: deleting its copy would race Try Again.
    func testSwapIsLiveUntilFinalized() throws {
        let schema = Schema([CompressionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let swap = try CompressionSwap(
            mediaType: .video,
            assetId: "live-test",
            originalSize: 100,
            exportPreset: "720p",
            modelContext: container.mainContext
        )
        XCTAssertTrue(CompressionSwap.isLive(assetId: "live-test"))
        swap.finalizeOriginalKept(copyRemoved: true)
        XCTAssertFalse(CompressionSwap.isLive(assetId: "live-test"))
    }

    /// A kept-both row whose copy the user later deleted in Photos must settle
    /// when its swap fails again: the pending-only lookup used to skip it, so
    /// the row kept naming an absent copy in `savedCopyIds` (blocking the
    /// original from every candidate list) while the UI reported the item as
    /// failed.
    func testMarkFailedSettlesKeptRowWhoseReplacementIsAbsent() async throws {
        let schema = Schema([CompressionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let swap = try CompressionSwap(
            mediaType: .video,
            assetId: "kept-gone",
            originalSize: 100,
            exportPreset: "720p",
            modelContext: context
        )
        swap.recordReplacement(id: "copy-1", size: 40)
        swap.finalizeKeptBoth()
        XCTAssertEqual(CompressionJournal.savedCopyIds(modelContext: context), ["copy-1"])

        await CompressionJournal.markPendingFailed(
            assetId: "kept-gone",
            replacementAbsent: true,
            modelContext: context
        )

        XCTAssertNil(CompressionJournal.savedCopyIds(modelContext: context).first, "the absent copy must leave `savedCopyIds`")
        let record = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompressionRecord>()).first
        )
        XCTAssertEqual(record.outcome, "failed")
        XCTAssertNil(record.replacementAssetLocalIdentifier)
        XCTAssertEqual(record.compressedSizeBytes, 0)
    }

    func testPhotoCompressionCandidatesSkipCopiesSmallAndHEIC() {
        func photo(_ id: String, size: Int64, file: String, live: Bool = false) -> AssetSummary {
            AssetSummary(
                id: id, mediaType: .photo, creationDate: nil, modificationDate: nil,
                pixelWidth: 4000, pixelHeight: 3000, duration: 0, fileSize: size,
                filename: file, isFavorite: false, isBurst: false, burstIdentifier: nil,
                isLivePhoto: live, isScreenshot: false, isLocallyAvailable: true
            )
        }
        let assets = [
            photo("big-jpg", size: 5_000_000, file: "IMG_1.JPG"),
            photo("small-jpg", size: 500_000, file: "IMG_2.JPG"),
            photo("big-heic", size: 5_000_000, file: "IMG_3.HEIC"),
            photo("copy", size: 5_000_000, file: "IMG_4.JPG"),
            photo("live", size: 5_000_000, file: "IMG_5.JPG", live: true)
        ]
        let large = PhotoCompressionViewModel.candidates(from: assets, excluding: ["copy"], showAll: false)
        XCTAssertEqual(large.map(\.id), ["big-jpg"])
        let all = PhotoCompressionViewModel.candidates(from: assets, excluding: ["copy"], showAll: true)
        XCTAssertEqual(all.map(\.id), ["big-jpg", "small-jpg", "big-heic"], "a compressed copy and a Live Photo are never listed")
    }

    func testIsUserDeclinedMatchesPhotoKitCancelOnly() {
        let declined = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.userCancelled.rawValue)
        let other = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.accessUserDenied.rawValue)
        XCTAssertTrue(PhotoServiceError.isUserDeclined(declined))
        XCTAssertTrue(PhotoServiceError.isUserDeclined(PhotoServiceError.userDeclined))
        XCTAssertFalse(PhotoServiceError.isUserDeclined(other))
        XCTAssertFalse(PhotoServiceError.isUserDeclined(PhotoServiceError.albumNotFound))
    }

    // MARK: - COMP-10: effectivePreset never upscales

    func testEffectivePresetStays1080pFor4KSource() {
        let asset = makeAsset(id: "a", pixelWidth: 3840, pixelHeight: 2160)
        let preset = VideoCompressionService.effectivePreset(for: asset, selected: CompressionPreset.presets[0])
        XCTAssertEqual(preset.id, "1080p")
    }

    func testEffectivePresetFallsBackTo720pFor720pSource() {
        let asset = makeAsset(id: "a", pixelWidth: 1280, pixelHeight: 720)
        let preset = VideoCompressionService.effectivePreset(for: asset, selected: CompressionPreset.presets[0])
        XCTAssertEqual(preset.id, "720p")
    }

    func testEffectivePresetFallsBackTo480pFor480pSource() {
        let asset = makeAsset(id: "a", pixelWidth: 640, pixelHeight: 480)
        let preset = VideoCompressionService.effectivePreset(for: asset, selected: CompressionPreset.presets[0])
        XCTAssertEqual(preset.id, "480p")
    }

    func testEffectivePresetSub480pSourceUsesSmallestPreset() {
        let asset = makeAsset(id: "a", pixelWidth: 320, pixelHeight: 240)
        let preset = VideoCompressionService.effectivePreset(for: asset, selected: CompressionPreset.presets[0])
        XCTAssertEqual(preset.id, "480p")
    }

    func testEffectivePresetNeverUpgradesSelection() {
        let asset4K = makeAsset(id: "a", pixelWidth: 3840, pixelHeight: 2160)
        XCTAssertEqual(VideoCompressionService.effectivePreset(for: asset4K, selected: CompressionPreset.presets[2]).id, "480p")
        XCTAssertEqual(VideoCompressionService.effectivePreset(for: asset4K, selected: CompressionPreset.presets[1]).id, "720p")
    }

    func testEffectivePresetUnknownDimensionsFallsBackToSmallest() {
        let asset = makeAsset(id: "a", pixelWidth: 0, pixelHeight: 0)
        let preset = VideoCompressionService.effectivePreset(for: asset, selected: CompressionPreset.presets[0])
        XCTAssertEqual(preset.id, "480p")
    }

    // MARK: - COMP-12: deterministic batch order

    func testSortedBatchIdsOrdersByFileSizeDescendingThenId() {
        let sizes: [String: Int64] = [
            "small": 10,
            "big": 1000,
            "medium": 500,
            "tie-a": 500,
            "tie-b": 500
        ]
        let ids = sortedBatchIds(selected: Set(sizes.keys), fileSizes: sizes)
        XCTAssertEqual(ids, ["big", "medium", "tie-a", "tie-b", "small"])
    }

    func testSortedBatchIdsMissingSizesFallbackToIdOrder() {
        let sizes: [String: Int64] = ["a": 10, "b": 0, "c": 0]
        let ids = sortedBatchIds(selected: Set(sizes.keys), fileSizes: sizes)
        XCTAssertEqual(ids, ["a", "b", "c"])
    }

    // MARK: - COMP-01: history totals exclude failed records

    func testCompressionRecordSucceededAndSavedBytes() {
        let completed = CompressionRecord(
            assetLocalIdentifier: "a",
            originalSizeBytes: 100,
            compressedSizeBytes: 40,
            exportPreset: "1080p",
            outcome: "completed"
        )
        XCTAssertTrue(completed.succeeded)
        XCTAssertEqual(completed.savedBytes, 60)

        let skipped = CompressionRecord(
            assetLocalIdentifier: "b",
            originalSizeBytes: 100,
            compressedSizeBytes: 100,
            exportPreset: "1080p",
            outcome: "skipped"
        )
        // A skipped record is a deliberate outcome (kept original, no savings),
        // not a failure — it must not render a red badge.
        XCTAssertFalse(skipped.succeeded)
        XCTAssertFalse(skipped.isFailed)
        XCTAssertEqual(skipped.savedBytes, 0)

        let failed = CompressionRecord(
            assetLocalIdentifier: "c",
            originalSizeBytes: 100,
            compressedSizeBytes: 0,
            exportPreset: "1080p",
            outcome: "failed"
        )
        XCTAssertFalse(failed.succeeded)
        XCTAssertTrue(failed.isFailed)
        // COMP-01: a failed record (compressedSizeBytes == 0) must not
        // contribute its whole original size as "savings".
        XCTAssertEqual(failed.savedBytes, 0)
    }

    func testHistoryTotalSavedExcludesFailedRecords() throws {
        let schema = Schema([CompressionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        context.insert(CompressionRecord(
            assetLocalIdentifier: "a",
            originalSizeBytes: 1_000,
            compressedSizeBytes: 400,
            exportPreset: "1080p",
            outcome: "completed"
        ))
        context.insert(CompressionRecord(
            assetLocalIdentifier: "b",
            originalSizeBytes: 2_000,
            compressedSizeBytes: 1_800,
            exportPreset: "720p",
            outcome: "skipped"
        ))
        context.insert(CompressionRecord(
            assetLocalIdentifier: "c",
            originalSizeBytes: 3_000,
            compressedSizeBytes: 0,
            exportPreset: "1080p",
            outcome: "failed"
        ))
        try context.save()

        let records = try context.fetch(FetchDescriptor<CompressionRecord>())
        let totalSaved = records.reduce(Int64(0)) { $0 + $1.savedBytes }
        // Only the completed record contributes (1000 - 400).
        XCTAssertEqual(totalSaved, 600)
    }

    // MARK: - COMP-16: only completed records block re-compression

    func testPreviouslyCompletedRecordDetection() throws {
        let schema = Schema([CompressionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        context.insert(CompressionRecord(
            assetLocalIdentifier: "done",
            originalSizeBytes: 100,
            compressedSizeBytes: 40,
            exportPreset: "1080p",
            outcome: "completed"
        ))
        context.insert(CompressionRecord(
            assetLocalIdentifier: "failed-once",
            originalSizeBytes: 100,
            compressedSizeBytes: 0,
            exportPreset: "1080p",
            outcome: "failed"
        ))
        try context.save()

        let completedIds = Set(((try? context.fetch(
            FetchDescriptor<CompressionRecord>(predicate: #Predicate { $0.outcome == "completed" })
        )) ?? []).map(\.assetLocalIdentifier))

        XCTAssertTrue(completedIds.contains("done"))
        XCTAssertFalse(completedIds.contains("failed-once"))
    }

    // MARK: - Kept-both durability (PR #2: kill with the Originals Kept
    // alert open must not delete the saved copy on next launch)

    func testKeptBothDeclineLeavesDurableNonPendingRow() throws {
        let schema = Schema([CompressionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let swap = try CompressionSwap(
            mediaType: .video,
            assetId: "kept-test",
            originalSize: 100,
            exportPreset: "720p",
            modelContext: context
        )
        swap.recordReplacement(id: "copy-1", size: 50)
        swap.finalizeKeptBoth()

        let records = try context.fetch(FetchDescriptor<CompressionRecord>())
        XCTAssertEqual(records.count, 1)
        let row = try XCTUnwrap(records.first)
        // Non-pending rows are invisible to reconcile, so a later launch can
        // never resolve this row to deleteOrphanThenFail.
        XCTAssertEqual(row.outcome, CompressionOutcome.kept.rawValue)
        XCTAssertTrue(row.isKept)
        XCTAssertFalse(row.succeeded)
        XCTAssertFalse(row.isFailed)
        XCTAssertEqual(row.savedBytes, 0)
        XCTAssertEqual(row.replacementAssetLocalIdentifier, "copy-1")
    }

    func testKeptBothRowPromotesToCompletedOnTryAgain() throws {
        let schema = Schema([CompressionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let swap = try CompressionSwap(
            mediaType: .video,
            assetId: "kept-promote-test",
            originalSize: 100,
            exportPreset: "720p",
            modelContext: context
        )
        swap.recordReplacement(id: "copy-1", size: 50)
        swap.finalizeKeptBoth()
        // finalizeKeptBoth deliberately leaves the swap live so Try Again can
        // still promote the row.
        swap.finalizeCompleted(compressedSize: 50)

        let records = try context.fetch(FetchDescriptor<CompressionRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.outcome, CompressionOutcome.completed.rawValue)
        XCTAssertTrue(records.first?.succeeded == true)
    }
}
