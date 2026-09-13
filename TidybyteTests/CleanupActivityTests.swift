import XCTest
import SwiftData
@testable import Tidybyte

/// Regression tests for the Activity & Savings ledger: the summary math, the
/// compression-history merge rules, and the write path that must never inflate
/// savings with failed or unconfirmed deletions.
final class CleanupActivityTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    /// `CleanupLedger` is a process-wide singleton; a test that attaches an
    /// in-memory container would otherwise leave it holding a torn-down store
    /// for every test that runs afterwards. Detach after each test so order
    /// can't matter.
    @MainActor
    override func tearDown() {
        CleanupLedger.shared.detach()
        super.tearDown()
    }

    // MARK: - Summary math

    func testLifetimeAndMonthTotalsSplitAtTheMonthBoundary() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let thisMonth = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
        let lastMonth = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20))!

        let summary = CleanupActivitySummary.build(
            events: [
                CleanupEvent(kind: .screenshots, itemCount: 3, freedBytes: 300, date: thisMonth),
                CleanupEvent(kind: .bursts, itemCount: 5, freedBytes: 500, date: lastMonth),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.lifetimeFreedBytes, 800)
        XCTAssertEqual(summary.lifetimeItemCount, 8)
        XCTAssertEqual(summary.monthFreedBytes, 300, "only the current month counts as 'this month'")
        XCTAssertFalse(summary.isEmpty)
    }

    func testDailyBucketsAreGapFilledToExactlyTheChartWindow() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
        let fiveDaysAgo = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let outsideWindow = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!

        let summary = CleanupActivitySummary.build(
            events: [
                CleanupEvent(kind: .swipe, itemCount: 1, freedBytes: 100, date: now),
                CleanupEvent(kind: .swipe, itemCount: 2, freedBytes: 50, date: fiveDaysAgo),
                CleanupEvent(kind: .swipe, itemCount: 9, freedBytes: 9_999, date: outsideWindow),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.daily.count, CleanupActivitySummary.chartWindowDays)
        XCTAssertEqual(summary.daily.last?.bytes, 100, "the last bucket is today")
        XCTAssertEqual(summary.daily.last?.itemCount, 1)
        // Gap-filled: the day between the two events exists with zero bytes.
        XCTAssertTrue(summary.daily.contains { $0.bytes == 0 })
        // Bytes older than the window are excluded from the chart but still
        // count toward lifetime (they are history, just not charted).
        XCTAssertEqual(summary.daily.reduce(Int64(0)) { $0 + $1.bytes }, 150)
        XCTAssertEqual(summary.lifetimeFreedBytes, 10_149)
        XCTAssertEqual(summary.activeDayCount, 2)
    }

    func testToolBreakdownSortsByBytesDescendingWithDeterministicTies() {
        let summary = CleanupActivitySummary.build(
            events: [
                CleanupEvent(kind: .screenshots, itemCount: 1, freedBytes: 500, date: .now),
                CleanupEvent(kind: .duplicates, itemCount: 4, freedBytes: 2_000, date: .now),
                CleanupEvent(kind: .bursts, itemCount: 2, freedBytes: 500, date: .now),
            ],
            now: .now,
            calendar: calendar
        )

        XCTAssertEqual(summary.byTool.first?.kind, .duplicates)
        // Equal bytes → raw value ascending, so the order can't flip between runs.
        XCTAssertEqual(summary.byTool.map(\.kind), [.duplicates, .bursts, .screenshots])
        XCTAssertEqual(summary.byTool.first?.count, 4, "counts are summed item counts, not event counts")
    }

    func testRecentIsNewestFirst() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let summary = CleanupActivitySummary.build(
            events: [
                CleanupEvent(kind: .swipe, itemCount: 1, freedBytes: 1, date: older),
                CleanupEvent(kind: .swipe, itemCount: 1, freedBytes: 1, date: newer),
            ],
            now: Date(timeIntervalSince1970: 3_000),
            calendar: calendar
        )
        XCTAssertEqual(summary.recent.map(\.date), [newer, older])
    }

    func testEmptyEventsProduceEmptyButWellFormedSummary() {
        let summary = CleanupActivitySummary.build(
            events: [],
            now: calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!,
            calendar: calendar
        )
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.lifetimeFreedBytes, 0)
        XCTAssertEqual(summary.byTool.count, 0)
        XCTAssertEqual(summary.daily.count, CleanupActivitySummary.chartWindowDays)
        XCTAssertEqual(summary.activeDayCount, 0)
    }

    // MARK: - Compression merge (COMP-01 parity)

    private func compressionRecord(
        outcome: CompressionOutcome,
        mediaType: CompressionMediaType,
        original: Int64,
        compressed: Int64
    ) -> CompressionRecord {
        CompressionRecord(
            assetLocalIdentifier: "asset-\(UUID().uuidString)",
            originalSizeBytes: original,
            compressedSizeBytes: compressed,
            compressedAt: Date(timeIntervalSince1970: 5_000),
            exportPreset: "test",
            outcome: outcome.rawValue,
            mediaType: mediaType.rawValue
        )
    }

    func testOnlyCompletedCompressionRowsContributeSavings() {
        let events = CleanupLedger.events(
            activityRecords: [],
            compressionRecords: [
                compressionRecord(outcome: .completed, mediaType: .video, original: 1_000, compressed: 400),
                compressionRecord(outcome: .pending, mediaType: .video, original: 1_000, compressed: 0),
                compressionRecord(outcome: .failed, mediaType: .video, original: 1_000, compressed: 0),
                compressionRecord(outcome: .skipped, mediaType: .video, original: 1_000, compressed: 900),
            ]
        )

        XCTAssertEqual(events.count, 1, "pending / failed / skipped rows are not cleanups")
        XCTAssertEqual(events.first?.freedBytes, 600)
        XCTAssertEqual(events.first?.itemCount, 1)
    }

    func testCompressionMediaTypesMapToDistinctBreakdownKinds() {
        let events = CleanupLedger.events(
            activityRecords: [],
            compressionRecords: [
                compressionRecord(outcome: .completed, mediaType: .video, original: 1_000, compressed: 500),
                compressionRecord(outcome: .completed, mediaType: .photo, original: 1_000, compressed: 500),
                compressionRecord(outcome: .completed, mediaType: .livePhoto, original: 1_000, compressed: 500),
                compressionRecord(outcome: .completed, mediaType: .still, original: 1_000, compressed: 500),
            ]
        )

        XCTAssertEqual(Set(events.map(\.kind)), [.videoCompression, .photoCompression, .livePhotos])
    }

    // MARK: - Ledger write path

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CleanupActivityRecord.self, CompressionRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    func testRecordCountsOnlyTheIdsItIsGivenAndTheirKnownSizes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let saved = AppPreferences.lifetimeFreed()
        defer { AppPreferences.saveLifetimeFreed(bytes: saved.bytes, items: saved.items) }

        CleanupLedger.shared.attach(modelContext: context)
        // "b" is iCloud-only → size unavailable (0). It still counts as an item
        // cleaned; it just can't contribute bytes.
        CleanupLedger.shared.record(
            kind: .screenshots,
            deletedIds: ["a", "b"],
            sizeOf: { ["a": 400, "b": 0][$0] ?? 0 }
        )

        let rows = try context.fetch(FetchDescriptor<CleanupActivityRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, CleanupActivityKind.screenshots.rawValue)
        XCTAssertEqual(rows.first?.itemCount, 2)
        XCTAssertEqual(rows.first?.freedBytes, 400)
        XCTAssertEqual(AppPreferences.lifetimeFreed().items, saved.items + 2)
        XCTAssertEqual(AppPreferences.lifetimeFreed().bytes, saved.bytes + 400)
    }

    @MainActor
    func testEmptyDeleteSetWritesNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext

        CleanupLedger.shared.attach(modelContext: context)
        CleanupLedger.shared.record(kind: .swipe, deletedIds: [], sizeOf: { _ in 1_000 })

        XCTAssertEqual(try context.fetch(FetchDescriptor<CleanupActivityRecord>()).count, 0)
    }

    @MainActor
    func testRecordBeforeAttachIsADroppedNoOpRatherThanACrash() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let saved = AppPreferences.lifetimeFreed()
        defer { AppPreferences.saveLifetimeFreed(bytes: saved.bytes, items: saved.items) }

        // Not attached (e.g. a delete finishing before the app wired the
        // context). Recording must not throw, must not touch the store, and
        // must not inflate the cached totals.
        CleanupLedger.shared.detach()
        CleanupLedger.shared.record(kind: .swipe, itemCount: 1, freedBytes: 500)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CleanupActivityRecord>()).count, 0)
        XCTAssertEqual(AppPreferences.lifetimeFreed().bytes, saved.bytes)
    }

    @MainActor
    func testRefreshCacheRepairsADriftedCache() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let saved = AppPreferences.lifetimeFreed()
        defer { AppPreferences.saveLifetimeFreed(bytes: saved.bytes, items: saved.items) }

        CleanupLedger.shared.attach(modelContext: context)
        CleanupLedger.shared.record(kind: .bursts, itemCount: 2, freedBytes: 750)

        // Simulate drift (interrupted insert, restore, manual meddling).
        AppPreferences.saveLifetimeFreed(bytes: 999_999_999, items: 99)
        CleanupLedger.shared.refreshCache(modelContext: context)

        // The store is the source of truth: the cache is rebuilt from the rows.
        XCTAssertEqual(AppPreferences.lifetimeFreed().bytes, 750)
        XCTAssertEqual(AppPreferences.lifetimeFreed().items, 2)
    }

    @MainActor
    func testRefreshCacheFoldsCompletedCompressionRowsIntoTheCachedTotals() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let saved = AppPreferences.lifetimeFreed()
        defer { AppPreferences.saveLifetimeFreed(bytes: saved.bytes, items: saved.items) }

        CleanupLedger.shared.attach(modelContext: context)
        context.insert(compressionRecord(outcome: .completed, mediaType: .video, original: 1_000, compressed: 250))
        context.insert(compressionRecord(outcome: .failed, mediaType: .video, original: 1_000, compressed: 0))
        try context.save()

        let summary = CleanupLedger.shared.refreshCache(modelContext: context)

        XCTAssertEqual(summary.lifetimeFreedBytes, 750, "failed rows contribute nothing")
        XCTAssertEqual(summary.lifetimeItemCount, 1)
        XCTAssertEqual(AppPreferences.lifetimeFreed().bytes, 750)
    }

    // MARK: - Kind → tool routing

    func testSwipeKindHasNoReviewToolButEveryOtherKindDoes() {
        XCTAssertNil(CleanupActivityKind.swipe.tool, "swipe is a session, not a cleanup tool")
        for kind in CleanupActivityKind.allCases where kind != .swipe {
            XCTAssertNotNil(kind.tool, "\(kind.rawValue) should route to a cleanup tool")
        }
    }

    func testKindTitlesAndIconsAreUniqueEnoughToRender() {
        for kind in CleanupActivityKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.icon.isEmpty)
        }
        XCTAssertEqual(CleanupActivityKind.swipe.title, "Swipe session")
        XCTAssertEqual(CleanupActivityKind.duplicates.title, CleanupTool.duplicates.name)
    }
}
