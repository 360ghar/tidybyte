import Foundation
import SwiftData

/// Append-only ledger of successful cleanups, plus the cached lifetime totals
/// that the widget and the non-launching `FreeSpaceIntent` read.
///
/// The SwiftData rows are the source of truth; the UserDefaults totals are a
/// read cache written on the same main-actor turn as the insert, and
/// reconciled from the store during the daily scan / after a library change.
/// An unattached ledger (no model context yet, e.g. very early launch) logs and
/// no-ops rather than crashing or blocking a delete the user already confirmed.
@MainActor
final class CleanupLedger {
    static let shared = CleanupLedger()

    private var modelContext: ModelContext?

    private init() {}

    /// Called once from the app entry point.
    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Drops the model context so `record` degrades to a logged no-op again.
    /// Exists for tests: this is a process-wide singleton, and a test that
    /// attaches an in-memory container would otherwise leave the ledger
    /// pointing at a torn-down store for every test that runs after it.
    func detach() {
        modelContext = nil
    }

    // MARK: - Recording

    func record(
        kind: CleanupActivityKind,
        itemCount: Int,
        freedBytes: Int64,
        at date: Date = .now
    ) {
        guard let modelContext else {
            AppLog.data.error("CleanupLedger.record called before attach; dropped \(kind.rawValue, privacy: .public)")
            return
        }
        let record = CleanupActivityRecord(
            kind: kind.rawValue,
            itemCount: itemCount,
            freedBytes: max(0, freedBytes),
            recordedAt: date
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            // A lost row only under-reports; the cache increment is skipped so
            // the two can't disagree in the other direction (over-reporting).
            AppLog.data.error("Failed to save cleanup activity: \(error.localizedDescription, privacy: .public)")
            return
        }
        AppPreferences.addLifetimeFreed(bytes: record.freedBytes, items: record.itemCount)
    }

    /// Convenience for the delete paths: counts only the ids the service
    /// confirmed deleted, and sizes each from the in-memory list captured
    /// before the delete (a post-delete fetch returns nothing).
    func record(
        kind: CleanupActivityKind,
        deletedIds: Set<String>,
        sizeOf: (String) -> Int64,
        at date: Date = .now
    ) {
        guard !deletedIds.isEmpty else { return }
        let bytes = deletedIds.reduce(Int64(0)) { $0 + max(0, sizeOf($1)) }
        record(kind: kind, itemCount: deletedIds.count, freedBytes: bytes, at: date)
    }

    // MARK: - Reconciliation

    /// Recomputes the cached totals from the store. Repairs any drift (an
    /// interrupted insert, a restore from backup, rows pruned by the user).
    /// Returns the summary it computed so callers that render it don't refetch.
    ///
    /// Failure contract: when either fetch fails, the store error is logged
    /// and the UserDefaults lifetime cache is left UNTOUCHED — overwriting it
    /// from a partial/empty fetch would zero lifetime totals the widget and
    /// intent read. The returned summary then carries the preserved cached
    /// totals so callers render last-known-good instead of zeros. (Returning
    /// `nil`/throwing would let screens distinguish fresh-vs-stale, but that
    /// changes this signature and needs matching edits in ActivityViewModel,
    /// StorageDashboardViewModel, and the tests.)
    @discardableResult
    func refreshCache(modelContext: ModelContext) -> CleanupActivitySummary {
        guard let activities = fetchActivityRecords(modelContext: modelContext),
              let compressions = fetchCompressionRecords(modelContext: modelContext) else {
            let cached = AppPreferences.lifetimeFreed()
            return CleanupActivitySummary(
                lifetimeFreedBytes: cached.bytes,
                lifetimeItemCount: cached.items
            )
        }
        let events = Self.events(
            activityRecords: activities,
            compressionRecords: compressions
        )
        let summary = CleanupActivitySummary.build(events: events)
        AppPreferences.saveLifetimeFreed(
            bytes: summary.lifetimeFreedBytes,
            items: summary.lifetimeItemCount
        )
        return summary
    }

    /// Nil when the store fetch fails (the error is logged). Callers must leave
    /// existing cached state alone rather than treat nil as "no records".
    private func fetchActivityRecords(modelContext: ModelContext) -> [CleanupActivityRecord]? {
        do {
            return try modelContext.fetch(FetchDescriptor<CleanupActivityRecord>())
        } catch {
            AppLog.data.error("Failed to fetch cleanup activity records for reconciliation: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Nil when the store fetch fails (the error is logged). Callers must leave
    /// existing cached state alone rather than treat nil as "no records".
    private func fetchCompressionRecords(modelContext: ModelContext) -> [CompressionRecord]? {
        do {
            return try modelContext.fetch(FetchDescriptor<CompressionRecord>())
        } catch {
            AppLog.data.error("Failed to fetch compression records for reconciliation: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Summary

    /// Maps both history tables into the pure `CleanupEvent` list the summary
    /// builder consumes. Compression rows follow the exact same inclusion rule
    /// as `CompressionHistoryView`: only `completed` swaps count, so pending /
    /// failed / skipped rows can never inflate lifetime savings (COMP-01).
    /// `nonisolated` so the mapping stays callable from the pure summary tests.
    nonisolated static func events(
        activityRecords: [CleanupActivityRecord],
        compressionRecords: [CompressionRecord]
    ) -> [CleanupEvent] {
        var events: [CleanupEvent] = activityRecords.compactMap { record in
            guard let kind = CleanupActivityKind(rawValue: record.kind) else { return nil }
            return CleanupEvent(
                kind: kind,
                itemCount: record.itemCount,
                freedBytes: record.freedBytes,
                date: record.recordedAt
            )
        }
        for record in compressionRecords where record.succeeded {
            events.append(CleanupEvent(
                kind: CleanupActivityKind.from(compressionMediaType: record.mediaType),
                itemCount: 1,
                freedBytes: record.savedBytes,
                date: record.compressedAt
            ))
        }
        return events
    }
}
