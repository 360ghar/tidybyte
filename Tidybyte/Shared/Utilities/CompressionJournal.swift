import Foundation
import Photos
import SwiftData

/// Crash-safety journal for the save-compressed-then-delete-original swap
/// performed by video/photo compression and Live Photo conversion (D1).
///
/// Without a journal, killing the app between "save replacement" and "delete
/// original" leaves a permanent duplicate in the library, and killing it
/// between "delete original" and "write the history row" silently loses the
/// COMP-16 guard (the replacement has a new id, so the item looks never-done).
///
/// Protocol per item:
/// 1. `beginPending` BEFORE the swap starts (outcome `"pending"`).
/// 2. `markSaveAttempted` immediately BEFORE the `performChanges` that writes
///    the replacement — i.e. after the export/encode/data-read phase, not
///    before it. This is what makes step 4's last case decidable.
/// 3. The service reports the replacement id + the real compressed size as
///    soon as the save commits; `recordReplacement` stores both on the
///    still-pending row.
/// 4. The normal completion path UPDATES that row to its final outcome.
/// 5. `reconcile` runs whenever a tool loads: every surviving pending row is
///    resolved against the current library —
///      - original gone, replacement journaled → the swap finished; finalize
///        as completed with the sizes journaled at save-commit time.
///      - original gone, no replacement → the user deleted the original
///        outside the swap; nothing to credit, mark failed.
///      - original + replacement   → crash hit the deadly window; delete the
///                                   orphaned replacement, mark failed.
///      - original only            → nothing durable happened; drop the row —
///                                   unless `saveAttempted` is set, in which
///                                   case the save had already begun and a
///                                   copy may exist that the journal cannot
///                                   name; surface it as failed instead of
///                                   hiding it.
///
/// `saveAttempted` (written by `markSaveAttempted` immediately before the
/// replacement `performChanges`) is what lets reconcile tell "we died during
/// the export" apart from "we died between the library write and the journal
/// update" — the first is safe to drop, the second may have stranded a copy.
/// Thrown when the journal itself cannot persist. The pending row is the
/// durability anchor for the whole save-then-delete swap — without it a crash
/// mid-swap is unrecoverable, so callers must abort the swap (not proceed
/// without a journal) when this surfaces.
enum CompressionJournalError: LocalizedError, Sendable {
    case beginPendingFailed(String)

    var errorDescription: String? {
        switch self {
        case .beginPendingFailed(let detail):
            "Could not save the pending compression record: \(detail)"
        }
    }
}

@MainActor
enum CompressionJournal {

    /// Inserts the pending row for `assetId`. Returns the record so callers can
    /// finalize the SAME row later (no lookup ambiguity across batch items).
    ///
    /// Throws when the insert cannot be persisted: the caller must abort the
    /// swap — proceeding without a durable pending row would leave a crash
    /// mid-swap unrecoverable (a permanent duplicate or a lost history guard).
    static func beginPending(
        modelContext: ModelContext,
        mediaType: CompressionMediaType,
        assetId: String,
        originalSize: Int64,
        compressedSize: Int64,
        exportPreset: String
    ) throws -> CompressionRecord {
        let record = CompressionRecord(
            assetLocalIdentifier: assetId,
            replacementAssetLocalIdentifier: nil,
            originalSizeBytes: originalSize,
            compressedSizeBytes: compressedSize,
            exportPreset: exportPreset,
            outcome: CompressionOutcome.pending.rawValue,
            mediaType: mediaType.rawValue
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            // Detach the undurable row so a later unrelated save cannot persist
            // it as a phantom pending row that reconcile would then chase.
            modelContext.delete(record)
            throw CompressionJournalError.beginPendingFailed(error.localizedDescription)
        }
        return record
    }

    /// Stores the replacement id + the real compressed size on the pending row
    /// the moment the save commits — the earliest point a crash could strand a
    /// duplicate. The size journaled here is what reconcile trusts when it
    /// finalizes a row whose bookkeeping was lost. `compressedSize` stays
    /// optional only as a default; video, photo, and Live Photo conversion
    /// all pass the real size at commit time.
    ///
    /// Deliberately best-effort (`try?`): unlike `beginPending`, the durable
    /// pending row already exists by the time this runs, so a failed save only
    /// delays bookkeeping that `finalize` (or `reconcile`, via `saveAttempted`)
    /// still resolves. Throwing here would also force the services'
    /// non-throwing `onReplacementSaved` callbacks to change signature.
    static func recordReplacement(
        _ record: CompressionRecord,
        replacementId: String,
        compressedSize: Int64? = nil,
        modelContext: ModelContext
    ) {
        record.replacementAssetLocalIdentifier = replacementId
        if let compressedSize {
            record.compressedSizeBytes = compressedSize
        }
        try? modelContext.save()
    }

    /// Marks the row as past the point where the library save has begun. MUST be
    /// called (and persisted) immediately BEFORE the `performChanges` that
    /// creates the replacement, and never before the export/data-read phase:
    /// from this moment on, a crash can leave a copy in the library whose id the
    /// journal never learned, and reconcile needs to know that.
    ///
    /// Deliberately best-effort (`try?`) for the same reason as
    /// `recordReplacement`: the pending row from `beginPending` is already
    /// durable, and the service `onSaveWillCommit` callbacks are non-throwing.
    static func markSaveAttempted(_ record: CompressionRecord, modelContext: ModelContext) {
        record.saveAttempted = true
        try? modelContext.save()
    }

    /// Finalizes the pending row with its real outcome (completed / skipped /
    /// failed). Sizes were captured at `beginPending`.
    static func finalize(
        _ record: CompressionRecord,
        outcome: CompressionOutcome,
        modelContext: ModelContext
    ) {
        record.outcome = outcome.rawValue
        try? modelContext.save()
    }

    /// Marks a still-pending journal row for this asset as failed (the swap
    /// attempt threw before or during completion), after removing any
    /// replacement that attempt stranded. No-op when no pending row exists.
    /// Shared by the photo/video batch loops (previously verbatim private copies
    /// in both view models).
    static func markPendingFailed(assetId: String, modelContext: ModelContext) async {
        await resolvePending(assetId: assetId, outcome: .failed, modelContext: modelContext)
    }

    /// Marks a still-pending row for an attempt that legitimately did not swap:
    /// an intentional skip (no savings), an iCloud-only size we refused to touch,
    /// or a user cancel. `CompressionRecord.isFailed` renders a red badge, so
    /// these must not be recorded as failures.
    static func markPendingSkipped(assetId: String, modelContext: ModelContext) async {
        await resolvePending(assetId: assetId, outcome: .skipped, modelContext: modelContext)
    }

    private static func resolvePending(
        assetId: String,
        outcome: CompressionOutcome,
        modelContext: ModelContext
    ) async {
        var descriptor = FetchDescriptor<CompressionRecord>(
            predicate: #Predicate { $0.outcome == "pending" && $0.assetLocalIdentifier == assetId }
        )
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        await resolveStrandedReplacement(of: record, outcome: outcome, modelContext: modelContext)
    }

    /// Finalizes a pending row for an attempt that ended without a swap, first
    /// removing the replacement it stranded (if any). The row is only finalized
    /// once the stranded copy is really gone: `reconcile` only looks at PENDING
    /// rows, so finalizing while a duplicate still exists would hide that
    /// duplicate from the cleanup permanently.
    private static func resolveStrandedReplacement(
        of record: CompressionRecord,
        outcome: CompressionOutcome,
        modelContext: ModelContext
    ) async {
        guard let orphanId = record.replacementAssetLocalIdentifier else {
            // Nothing durable was ever saved (or a rollback already removed it).
            finalize(record, outcome: outcome, modelContext: modelContext)
            return
        }
        guard await PhotoLibraryService.shared.removeOrphanedAsset(id: orphanId) else {
            AppLog.compression.error(
                "Could not remove stranded replacement \(orphanId, privacy: .public); leaving the journal row pending so the next reconcile retries"
            )
            return
        }
        // The copy this row described is gone — zero its size so History doesn't
        // advertise a compression that no longer exists (the same invariant
        // COMP-01 relies on: non-completed rows carry compressedSizeBytes == 0).
        record.replacementAssetLocalIdentifier = nil
        record.compressedSizeBytes = 0
        finalize(record, outcome: outcome, modelContext: modelContext)
    }

    /// What reconcile should do with one leftover pending row. Split out as a
    /// pure decision table so the crash-window semantics are unit-testable —
    /// `reconcile` itself needs a live photo library to exercise the
    /// "original still present" branches.
    enum Resolution: Equatable, Sendable {
        /// Original gone + replacement journaled: the swap finished; the
        /// journaled compressed size is real.
        case completed
        /// Original gone, no replacement journaled: the user deleted the
        /// original outside the swap — nothing to credit, so record a failure
        /// instead of phantom savings.
        case failed
        /// Both copies exist: remove the orphaned replacement, then fail.
        case deleteOrphanThenFail(id: String)
        /// A library write had begun but its id never reached the journal, so a
        /// copy may exist that we cannot name. Surface it as a failed attempt —
        /// dropping the row would hide that duplicate from every cleanup path.
        case failedWithPossibleOrphan
        /// Nothing durable happened (the attempt died before any library write).
        case dropRow
    }

    nonisolated static func resolution(
        originalExists: Bool,
        replacementId: String?,
        saveAttempted: Bool
    ) -> Resolution {
        switch (originalExists, replacementId) {
        case (false, .some):
            return .completed
        case (false, .none):
            return .failed
        case (true, .some(let orphanId)):
            return .deleteOrphanThenFail(id: orphanId)
        case (true, .none):
            return saveAttempted ? .failedWithPossibleOrphan : .dropRow
        }
    }

    /// Resolves every leftover pending row against the live library (see the
    /// type doc). Called on tool load; failures are logged, never fatal.
    /// Rows with the kept-both outcome are terminal and never reach this
    /// method: the fetch below is pending-only, so a decline settled durably
    /// by `CompressionSwap.finalizeKeptBoth` can never resolve to
    /// `deleteOrphanThenFail` and lose the user's saved copy.
    /// Assets that already have a usable copy (completed swaps, no-savings
    /// skips, kept-both declines). Failed rows, and skips whose copies were
    /// removed, stay eligible for another try.
    static func alreadyCompressedIds(modelContext: ModelContext) -> Set<String> {
        let records = (try? modelContext.fetch(FetchDescriptor<CompressionRecord>(
            predicate: #Predicate { $0.outcome != "pending" && $0.outcome != "failed" }
        ))) ?? []
        return Set(records.filter { $0.replacementAssetLocalIdentifier != nil }.map(\.assetLocalIdentifier))
    }

    /// Copies this app made that are still named on a settled row: completed
    /// swaps, and copies the user chose to keep next to the original.
    static func savedCopyIds(modelContext: ModelContext) -> Set<String> {
        let records = (try? modelContext.fetch(FetchDescriptor<CompressionRecord>(
            predicate: #Predicate { $0.outcome != "pending" }
        ))) ?? []
        return Set(records.compactMap(\.replacementAssetLocalIdentifier))
    }

    static func reconcile(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<CompressionRecord>(
            predicate: #Predicate { $0.outcome == "pending" }
        )
        guard let pendings = try? modelContext.fetch(descriptor), !pendings.isEmpty else { return }
        AppLog.compression.info("Reconciling \(pendings.count, privacy: .public) pending compression record(s)")
        var resolved: [(CompressionRecord, Resolution)] = []
        // Rows still owned by a live swap (a running batch, or saved copies
        // waiting on the Originals Kept choice) are not crash leftovers.
        let leftovers = pendings.filter { !CompressionSwap.isLive(assetId: $0.assetLocalIdentifier) }
        let existingOriginals = await PhotoLibraryService.shared.existingIds(leftovers.map(\.assetLocalIdentifier))
        for record in leftovers {
            resolved.append((record, Self.resolution(
                originalExists: existingOriginals.contains(record.assetLocalIdentifier),
                replacementId: record.replacementAssetLocalIdentifier,
                saveAttempted: record.saveAttempted
            )))
        }

        // Remove every stranded replacement in ONE call, so the user sees one
        // iOS delete prompt instead of one per row.
        let orphanIds = resolved.compactMap { _, resolution -> String? in
            if case .deleteOrphanThenFail(let id) = resolution { return id }
            return nil
        }
        let removedOrphans = await PhotoLibraryService.shared.removeOrphanedAssets(ids: orphanIds)

        for (record, resolution) in resolved {
            switch resolution {
            case .completed:
                // Original gone and a replacement was journaled: the swap
                // completed; only the bookkeeping was lost. The compressed size
                // was journaled at recordReplacement time, so the finalized
                // savings are real (not originalSize - 0).
                record.outcome = "completed"
            case .failed:
                record.outcome = "failed"
            case .deleteOrphanThenFail(let orphanId):
                // Deadly window: both copies exist. Roll forward by removing
                // the orphaned replacement (the original is untouched and
                // remains the user's copy), then mark failed so the user sees
                // the item again. If the removal fails the row stays PENDING so
                // the next reconcile retries instead of hiding the duplicate
                // for good.
                guard removedOrphans.contains(orphanId) else {
                    AppLog.compression.error(
                        "Reconcile could not remove stranded replacement \(orphanId, privacy: .public); will retry on the next load"
                    )
                    continue
                }
                record.replacementAssetLocalIdentifier = nil
                record.outcome = "failed"
            case .failedWithPossibleOrphan:
                // The journal cannot name the copy, so it cannot remove it —
                // the honest thing is to leave a failed row the user can see.
                AppLog.compression.error(
                    "Interrupted compression for \(record.assetLocalIdentifier, privacy: .public): the library save had started but no replacement id was journaled — a duplicate may exist"
                )
                record.outcome = "failed"
            case .dropRow:
                modelContext.delete(record)
            }
        }
        try? modelContext.save()
    }
}

extension PhotoLibraryService {
    /// Best-effort deletion used only by journal reconciliation (no UI context,
    /// no selection semantics — just remove the stranded copy). Returns whether
    /// the asset is really gone. Callers MUST check the result rather than
    /// assume success: `deleteAssets` reports success as a *subset* of the
    /// identifiers it was given, and its per-identifier fallback throws
    /// `partialDeletion` carrying the ids that DID succeed when it is
    /// cancelled (or partially fails) — `removeOrphanedAssets` recovers that
    /// partial set from the error below instead of dropping it.
    fileprivate func removeOrphanedAsset(id: String) async -> Bool {
        await removeOrphanedAssets(ids: [id]).contains(id)
    }

    /// Batch form: one `deleteAssets` call (one iOS prompt). Returns the ids
    /// that are really gone, including those removed by a partial failure.
    fileprivate func removeOrphanedAssets(ids: [String]) async -> Set<String> {
        guard !ids.isEmpty else { return [] }
        do {
            return try await deleteAssets(identifiers: ids)
        } catch {
            return (error as? PhotoServiceError)?.succeededIds ?? []
        }
    }
}