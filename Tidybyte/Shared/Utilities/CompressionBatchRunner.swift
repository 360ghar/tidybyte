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
    case completed(originalSize: Int64, compressedSize: Int64)
}

/// Owns one journal row: begin → optional progress hooks → exactly one terminal.
/// `finished` guard makes double-finalize impossible.
@MainActor
final class CompressionSwap {
    private let record: CompressionRecord
    private let modelContext: ModelContext
    private var finished = false

    init(
        mediaType: CompressionMediaType,
        assetId: String,
        originalSize: Int64,
        exportPreset: String,
        modelContext: ModelContext
    ) {
        self.modelContext = modelContext
        self.record = CompressionJournal.beginPending(
            modelContext: modelContext,
            mediaType: mediaType,
            assetId: assetId,
            originalSize: originalSize,
            compressedSize: 0,
            exportPreset: exportPreset
        )
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
        guard !finished else { return }
        finished = true
        record.compressedSizeBytes = compressedSize
        CompressionJournal.finalize(record, outcome: .completed, modelContext: modelContext)
    }

    func finalizeSkipped() {
        guard !finished else { return }
        finished = true
        CompressionJournal.finalize(record, outcome: .skipped, modelContext: modelContext)
    }

    func markFailed(assetId: String) async {
        guard !finished else { return }
        finished = true
        await CompressionJournal.markPendingFailed(assetId: assetId, modelContext: modelContext)
    }

    func markSkipped(assetId: String) async {
        guard !finished else { return }
        finished = true
        await CompressionJournal.markPendingSkipped(assetId: assetId, modelContext: modelContext)
    }
}

@MainActor
enum CompressionBatchRunner {
    struct Handlers: Sendable {
        var setExporting: @MainActor @Sendable (Int, Float) -> Void
        var setKeptOriginal: @MainActor @Sendable (Int, String) -> Void
        var setCompleted: @MainActor @Sendable (Int, Int64) -> Void
        var setFailed: @MainActor @Sendable (Int, String) -> Void
        var setWaiting: @MainActor @Sendable (Int) -> Void
    }

    struct Result: Sendable {
        var successfulIds: Set<String>
        var summary: CompressionBatchSummary
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
        var successfulIds: Set<String> = []
        var completed = 0, failed = 0, skipped = 0
        for id in orderedIds {
            if isCancelled() { break }
            guard let index = indexById[id] else { continue }
            if alreadyCompletedIds.contains(id) {
                handlers.setKeptOriginal(index, "Already compressed")
                skipped += 1
                continue
            }
            handlers.setExporting(index, 0)
            do {
                let outcome = try await execute(id, index, { p in handlers.setExporting(index, p) })
                switch outcome {
                case .skipped:
                    skipped += 1
                case .completed(let orig, let comp):
                    completed += 1
                    successfulIds.insert(id)
                    handlers.setCompleted(index, max(0, orig - comp))
                }
            } catch {
                if isCancelled() || error is CancellationError {
                    handlers.setWaiting(index)
                    break
                }
                if isSizeUnknown(error) {
                    handlers.setKeptOriginal(index, "Size unknown (iCloud-only) — skipped")
                    skipped += 1
                    continue
                }
                failed += 1
                handlers.setFailed(index, error.localizedDescription)
            }
        }
        return Result(
            successfulIds: successfulIds,
            summary: CompressionBatchSummary(
                completed: completed,
                failed: failed,
                skipped: skipped,
                cancelled: isCancelled()
            )
        )
    }
}
