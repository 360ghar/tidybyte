import Photos
import SwiftData

/// Shared per-item loop for the photo + video batch compressions (COMP-12).
///
/// Both stacks share one loop shape: deterministic order, already-completed
/// skip, per-item journal swap, skipped/completed/cancel/sizeUnknown/failed
/// branches, and a counted summary. The loop bodies differed in exactly four
/// places (preset resolution, journal mediaType, skip-error type, service
/// entry), so the runner owns counting/summary/row-state while each VM's
/// `execute` closure owns the full journal-swap lifecycle (it alone knows the
/// resolved exportPreset id).

enum CompressionItemOutcome: Sendable {
    case skipped
    /// The copy is saved; the original waits for the batch's one delete commit.
    case saved(PendingOriginal)
}

/// A saved copy whose original is still in the library. The batch deletes all
/// originals in one `OriginalsCommit.commit` call, so iOS shows one delete
/// prompt per batch instead of one per item.
struct PendingOriginal: Sendable {
    let assetId: String
    let originalSize: Int64
    let compressedSize: Int64
    let swap: CompressionSwap
}

/// Status text for the two steps of a replace batch.
enum ReplacePhase: Equatable, Sendable {
    case idle
    case savingCopies(done: Int, total: Int)
    case removingOriginals(count: Int)
}

/// Owns one journal row: begin → optional progress hooks → exactly one terminal.
/// `finished` guard makes double-finalize impossible.
///
/// The initializer throws when the pending row cannot be persisted
/// (`CompressionJournalError`): callers must let that abort the item's swap —
/// running the save-then-delete without a durable journal row is what strands
/// unrecoverable duplicates.
@MainActor
final class CompressionSwap {
    private let record: CompressionRecord
    private let modelContext: ModelContext
    private let assetId: String
    private var finished = false

    /// Swaps that are still running or waiting for the delete-originals
    /// commit. Weak, so a swap dropped with its view model stops counting.
    private struct WeakSwap { weak var swap: CompressionSwap? }
    private static var liveSwaps: [String: WeakSwap] = [:]

    /// True while an in-memory swap still owns the pending row for this
    /// asset. `reconcile` must skip such rows: they are not crash leftovers,
    /// and deleting their copies would race the Originals Kept choice.
    static func isLive(assetId: String) -> Bool {
        liveSwaps[assetId]?.swap != nil
    }

    /// Marks the swap finished. Returns false when it already was.
    private func finish() -> Bool {
        guard beginFinish() else { return false }
        endFinish()
        return true
    }

    /// Claims the finished flag without unregistering the live swap. The async
    /// terminal paths (markFailed/markSkipped) use this plus `endFinish`, so
    /// `reconcile` (which skips live rows) cannot grab the row while the
    /// journal resolution is still in flight.
    private func beginFinish() -> Bool {
        guard !finished else { return false }
        finished = true
        return true
    }

    private func endFinish() {
        // Only clear our own entry: a newer swap for the same asset may own it.
        if Self.liveSwaps[assetId]?.swap === self {
            Self.liveSwaps[assetId] = nil
        }
    }

    init(
        mediaType: CompressionMediaType,
        assetId: String,
        originalSize: Int64,
        exportPreset: String,
        modelContext: ModelContext
    ) throws {
        self.modelContext = modelContext
        self.assetId = assetId
        self.record = try CompressionJournal.beginPending(
            modelContext: modelContext,
            mediaType: mediaType,
            assetId: assetId,
            originalSize: originalSize,
            compressedSize: 0,
            exportPreset: exportPreset
        )
        Self.liveSwaps[assetId] = WeakSwap(swap: self)
    }

    var replacementId: String? { record.replacementAssetLocalIdentifier }

    /// Settles a row whose original was kept. The row stops being pending, so
    /// reconcile never deletes anything for it later. When both versions stay
    /// (`copyRemoved == false`) the row records the kept-both outcome and the
    /// copy's id is kept on the row, so Photo Compression knows it is a copy
    /// and never lists it for compression.
    func finalizeOriginalKept(copyRemoved: Bool) {
        guard finish() else { return }
        if copyRemoved {
            record.replacementAssetLocalIdentifier = nil
            record.compressedSizeBytes = 0
            CompressionJournal.finalize(record, outcome: .skipped, modelContext: modelContext)
        } else {
            finalizeKeptBoth()
        }
    }

    /// Settles a decline durably the moment it happens: the row leaves
    /// "pending" with the kept-both outcome, so killing the app with the
    /// Originals Kept alert open can never turn into a reconcile
    /// `deleteOrphanThenFail` that deletes the saved copy on next launch.
    /// Deliberately does NOT consume `finish()`: a later Try Again promotes
    /// kept → completed through `finalizeCompleted`, and Remove Copies
    /// settles through `finalizeOriginalKept`.
    func finalizeKeptBoth() {
        CompressionJournal.finalize(record, outcome: .kept, modelContext: modelContext)
    }

    func markSaveAttempted() {
        CompressionJournal.markSaveAttempted(record, modelContext: modelContext)
    }

    func recordReplacement(id: String, size: Int64) {
        CompressionJournal.recordReplacement(
            record,
            replacementId: id,
            compressedSize: size,
            modelContext: modelContext
        )
    }

    func finalizeCompleted(compressedSize: Int64) {
        guard finish() else { return }
        record.compressedSizeBytes = compressedSize
        CompressionJournal.finalize(record, outcome: .completed, modelContext: modelContext)
    }

    func finalizeSkipped() {
        guard finish() else { return }
        CompressionJournal.finalize(record, outcome: .skipped, modelContext: modelContext)
    }

    func markFailed(assetId: String) async {
        guard beginFinish() else { return }
        await CompressionJournal.markPendingFailed(assetId: assetId, modelContext: modelContext)
        endFinish()
    }

    func markSkipped(assetId: String) async {
        guard beginFinish() else { return }
        await CompressionJournal.markPendingSkipped(assetId: assetId, modelContext: modelContext)
        endFinish()
    }
}

@MainActor
enum CompressionBatchRunner {
    struct Handlers: Sendable {
        /// Sets the row state at an index into the VM's list.
        var setState: @MainActor @Sendable (Int, CompressionState) -> Void
        var setPhase: @MainActor @Sendable (ReplacePhase) -> Void
    }

    struct Result: Sendable {
        var successfulIds: Set<String>
        var summary: CompressionBatchSummary
        /// Saved copies whose originals are still in the library (the user
        /// tapped "Don't Allow", or the delete failed). The view offers
        /// Try Again / Remove Copies for these.
        var kept: [PendingOriginal]
    }

    // Runs the per-item loop. `execute` creates its CompressionSwap (it alone
    // knows the resolved preset id) and MUST terminally settle it on every path.
    static func run(
        selected: Set<String>,
        fileSizes: [String: Int64],
        indexById: [String: Int],
        alreadyCompletedIds: Set<String>,
        isCancelled: @MainActor @Sendable () -> Bool,
        isSizeUnknown: @MainActor @Sendable (Error) -> Bool,
        modelContext: ModelContext,
        handlers: Handlers,
        execute: @MainActor @Sendable (String, Int, @escaping @MainActor @Sendable (Float) -> Void) async throws
            -> CompressionItemOutcome
    ) async -> Result {
        let orderedIds = sortedBatchIds(selected: selected, fileSizes: fileSizes)
        var saved: [PendingOriginal] = []
        var failed = 0, skipped = 0
        for (offset, id) in orderedIds.enumerated() {
            if offset % 20 == 0 { await Task.yield() }
            if isCancelled() { break }
            handlers.setPhase(.savingCopies(done: offset, total: orderedIds.count))
            guard let index = indexById[id] else { continue }
            if alreadyCompletedIds.contains(id) {
                handlers.setState(index, .keptOriginal(reason: "Already compressed"))
                skipped += 1
                continue
            }
            handlers.setState(index, .exporting(0))
            do {
                let outcome = try await execute(id, index, { p in handlers.setState(index, .exporting(p)) })
                switch outcome {
                case .skipped:
                    skipped += 1
                case .saved(let pending):
                    saved.append(pending)
                    handlers.setState(index, .copySaved)
                }
            } catch {
                if isCancelled() || error is CancellationError {
                    handlers.setState(index, .waiting)
                    break
                }
                if isSizeUnknown(error) {
                    handlers.setState(index, .keptOriginal(reason: "Size unknown (iCloud-only) — skipped"))
                    skipped += 1
                    continue
                }
                failed += 1
                handlers.setState(index, .failed(error.localizedDescription))
            }
        }

        // Step 2: every copy is saved. Delete all originals at once — one iOS
        // prompt. This also runs after a cancel, so finished items finish.
        var successfulIds: Set<String> = []
        var kept: [PendingOriginal] = []
        if !saved.isEmpty {
            handlers.setPhase(.removingOriginals(count: saved.count))
            let outcome = await OriginalsCommit.commit(saved)
            for item in outcome.committed {
                successfulIds.insert(item.assetId)
                if let index = indexById[item.assetId] {
                    handlers.setState(index, .completed(savedBytes: max(0, item.originalSize - item.compressedSize)))
                }
            }
            kept = outcome.kept
        }
        handlers.setPhase(.idle)
        return Result(
            successfulIds: successfulIds,
            summary: CompressionBatchSummary(
                completed: successfulIds.count,
                failed: failed,
                skipped: skipped,
                cancelled: isCancelled()
            ),
            kept: kept
        )
    }
}

/// Step 2 of every replace flow (video, photo, Live Photo): delete the
/// originals of saved copies in ONE PhotoKit call, so the user sees one iOS
/// prompt per batch.
@MainActor
enum OriginalsCommit {
    struct Outcome: Sendable {
        var committed: [PendingOriginal]
        var kept: [PendingOriginal]
    }

    /// Splits items by whether their original is still in the library. The
    /// library is the truth, not `deleteAssets`' return set: an original that
    /// vanished outside the app is also done.
    nonisolated static func partition<T>(
        _ items: [T],
        id: (T) -> String,
        stillPresent: Set<String>
    ) -> (committed: [T], kept: [T]) {
        var committed: [T] = [], kept: [T] = []
        for item in items {
            if stillPresent.contains(id(item)) { kept.append(item) } else { committed.append(item) }
        }
        return (committed, kept)
    }

    /// Shown when the user also declines Remove Copies.
    static let copiesKeptMessage = "Copies kept. Both versions are in your library; delete either one in Photos."

    /// `commit`, with the bottom bar showing "removing originals" while it runs.
    static func commit(
        _ pending: [PendingOriginal],
        setPhase: (ReplacePhase) -> Void
    ) async -> Outcome {
        setPhase(.removingOriginals(count: pending.count))
        let outcome = await commit(pending)
        setPhase(.idle)
        return outcome
    }

    static func commit(
        _ pending: [PendingOriginal],
        photoService: PhotoLibraryService = .shared
    ) async -> Outcome {
        guard !pending.isEmpty else { return Outcome(committed: [], kept: []) }
        // Never delete an original whose copy is gone: verify replacements
        // first and fail those items out without touching their originals.
        let replacementIds = pending.compactMap(\.swap.replacementId)
        let existingReplacements = await photoService.existingIds(replacementIds)
        var viable: [PendingOriginal] = []
        viable.reserveCapacity(pending.count)
        for item in pending {
            guard let replacementId = item.swap.replacementId,
                  existingReplacements.contains(replacementId) else {
                await item.swap.markFailed(assetId: item.assetId)
                continue
            }
            viable.append(item)
        }
        guard !viable.isEmpty else { return Outcome(committed: [], kept: []) }
        let ids = viable.map(\.assetId)
        // A decline or a partial failure throws; the presence check below
        // decides what happened either way.
        _ = try? await photoService.deleteAssets(identifiers: ids)
        let split = partition(viable, id: \.assetId, stillPresent: await photoService.existingIds(ids))
        for item in split.committed {
            item.swap.finalizeCompleted(compressedSize: item.compressedSize)
        }
        // Decline path: settle every kept row durably NOW (kept-both outcome),
        // not via the in-memory alert alone — otherwise killing the app before
        // Try Again / Remove Copies leaves pending rows whose copies the next
        // reconcile deletes as orphans. The swap stays promotable, so Try
        // Again still finalizes these rows as completed on success.
        for item in split.kept {
            item.swap.finalizeKeptBoth()
        }
        return Outcome(committed: split.committed, kept: split.kept)
    }

    /// The user kept the originals and chose "Remove Copies": delete the new
    /// copies in one call (one iOS prompt). If they decline that too, both
    /// versions stay and the journal stops tracking the copies.
    /// Returns false when some copies are still there (the user declined).
    @discardableResult
    static func removeCopies(
        _ kept: [PendingOriginal],
        photoService: PhotoLibraryService = .shared
    ) async -> Bool {
        // An original that vanished outside the app is already replaced: the
        // end state holds, so complete those rows and never touch their copies.
        let existingOriginals = await photoService.existingIds(kept.map(\.assetId))
        var active: [PendingOriginal] = []
        active.reserveCapacity(kept.count)
        for item in kept {
            if existingOriginals.contains(item.assetId) {
                active.append(item)
            } else {
                item.swap.finalizeCompleted(compressedSize: item.compressedSize)
            }
        }
        let copyIds = active.compactMap(\.swap.replacementId)
        if !copyIds.isEmpty {
            _ = try? await photoService.deleteAssets(identifiers: copyIds)
        }
        let stillPresent = await photoService.existingIds(copyIds)
        for item in active {
            let copyGone = item.swap.replacementId.map { !stillPresent.contains($0) } ?? true
            item.swap.finalizeOriginalKept(copyRemoved: copyGone)
        }
        return stillPresent.isEmpty
    }
}
