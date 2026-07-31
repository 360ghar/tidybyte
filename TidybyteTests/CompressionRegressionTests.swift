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
        XCTAssertFalse(skipped.succeeded)
        XCTAssertEqual(skipped.savedBytes, 0)

        let failed = CompressionRecord(
            assetLocalIdentifier: "c",
            originalSizeBytes: 100,
            compressedSizeBytes: 0,
            exportPreset: "1080p",
            outcome: "failed"
        )
        XCTAssertFalse(failed.succeeded)
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
}
