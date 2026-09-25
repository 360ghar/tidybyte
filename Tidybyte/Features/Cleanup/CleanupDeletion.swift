import Foundation

/// Shared delete pipeline for cleanup tools. Owns delete → ledger → reconcile;
/// callers own the re-entry guard + isDeleting flag (an inout flag cannot cross
/// the service await). Each tool supplies list surgery as `apply`.
@MainActor
enum CleanupDeletion {
    /// Shown in every delete confirm. PhotoKit deletes go to Recently Deleted,
    /// so "cannot be undone" was false and scared users.
    static let recoverableNote = "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days."

    struct Outcome {
        let removed: Set<String>       // confirmed deleted or already absent
        let errorMessage: String?      // nil on full success; set on partial + hard failure
        let deletedCount: Int?         // what deletedCount must be assigned; nil when guard rejected
    }

    /// `requestedIds` must be pre-resolved by the caller (tab-union, or
    /// visible-intersection for LargeFiles). `recordDeleted` nil for tools
    /// without deletedCount (LargeFiles, Bursts).
    static func delete(
        requestedIds: Set<String>,
        kind: CleanupActivityKind,
        sizeById: [String: Int64],
        performDelete: @MainActor ([String]) async throws -> PhotoDeletionOutcome = {
            try await PhotoLibraryService.shared.deleteAssets(identifiers: $0)
        },
        apply: (Set<String>) -> Void,
        recordDeleted: ((Int) -> Void)? = nil
    ) async -> Outcome {
        guard !requestedIds.isEmpty else {
            return Outcome(removed: [], errorMessage: nil, deletedCount: nil)
        }
        do {
            let result = try await performDelete(Array(requestedIds))
            let deletedIds = result.deletedIds
            recordDeleted?(deletedIds.count)
            CleanupLedger.shared.record(kind: kind, deletedIds: deletedIds, sizeOf: { sizeById[$0] ?? 0 })
            apply(result.removedIds)
            return Outcome(removed: result.removedIds, errorMessage: nil, deletedCount: deletedIds.count)
        } catch is CancellationError {
            // A cancel is not a deletion failure: nothing was deleted, so stay
            // quiet rather than reporting "Deleted 0 of N items. N couldn't be
            // deleted. Try again." and inviting a pointless re-confirm.
            return Outcome(removed: [], errorMessage: nil, deletedCount: nil)
        } catch let error as PhotoServiceError {
            if let result = error.deletionOutcome {
                let succeededIds = result.deletedIds
                recordDeleted?(succeededIds.count)
                CleanupLedger.shared.record(kind: kind, deletedIds: succeededIds, sizeOf: { sizeById[$0] ?? 0 })
                apply(result.removedIds)
                return Outcome(removed: result.removedIds, errorMessage: error.localizedDescription, deletedCount: succeededIds.count)
            }
            // "Don't Allow" keeps its "Nothing was deleted." message: the
            // views gate the success celebration on `errorMessage == nil`.
            return Outcome(removed: [], errorMessage: error.localizedDescription, deletedCount: nil)
        } catch {
            return Outcome(removed: [], errorMessage: error.localizedDescription, deletedCount: nil)
        }
    }
}
