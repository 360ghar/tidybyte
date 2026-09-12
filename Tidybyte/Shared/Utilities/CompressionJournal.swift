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
@MainActor
enum CompressionJournal {

    /// Inserts the pending row for `assetId`. Returns the record so callers can
    /// finalize the SAME row later (no lookup ambiguity across batch items).
    static func beginPending(
        modelContext: ModelContext,
        mediaType: CompressionMediaType,
        assetId: String,
        originalSize: Int64,
        compressedSize: Int64,
        exportPreset: String
    ) -> CompressionRecord {
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
        try? modelContext.save()
        return record
    }

    /// Stores the replacement id + the real compressed size on the pending row
    /// the moment the save commits — the earliest point a crash could strand a
    /// duplicate. The size journaled here is what reconcile trusts when it
    /// finalizes a row whose bookkeeping was lost. `compressedSize` stays
    /// optional only as a default; video, photo, and Live Photo conversion
    /// all pass the real size at commit time.
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
    static func reconcile(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<CompressionRecord>(
            predicate: #Predicate { $0.outcome == "pending" }
        )
        guard let pendings = try? modelContext.fetch(descriptor), !pendings.isEmpty else { return }
        AppLog.compression.info("Reconciling \(pendings.count, privacy: .public) pending compression record(s)")
        for record in pendings {
            let originalExists = PHAsset.fetchAssets(
                withLocalIdentifiers: [record.assetLocalIdentifier],
                options: nil
            ).firstObject != nil
            let resolution = Self.resolution(
                originalExists: originalExists,
                replacementId: record.replacementAssetLocalIdentifier,
                saveAttempted: record.saveAttempted
            )

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
                guard await PhotoLibraryService.shared.removeOrphanedAsset(id: orphanId) else {
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
    /// identifiers it was given, and its per-identifier fallback returns a
    /// partial (or empty) set without throwing when it is cancelled.
    fileprivate func removeOrphanedAsset(id: String) async -> Bool {
        let deleted = (try? await deleteAssets(identifiers: [id])) ?? []
        return deleted.contains(id)
    }
}