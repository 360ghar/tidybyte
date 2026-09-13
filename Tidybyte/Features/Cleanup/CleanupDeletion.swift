import Foundation

/// Shared delete pipeline for cleanup tools. Owns delete → ledger → reconcile;
/// callers own the re-entry guard + isDeleting flag (an inout flag cannot cross
/// the service await). Each tool supplies list surgery as `apply`.
@MainActor
enum CleanupDeletion {
    struct Outcome {
        let removed: Set<String>       // confirmed deleted; empty on total failure
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
        photoService: PhotoLibraryService = .shared,
        apply: (Set<String>) -> Void,
        recordDeleted: ((Int) -> Void)? = nil
    ) async -> Outcome {
        guard !requestedIds.isEmpty else {
            return Outcome(removed: [], errorMessage: nil, deletedCount: nil)
        }
        do {
            let deletedIds = try await photoService.deleteAssets(identifiers: Array(requestedIds))
            recordDeleted?(deletedIds.count)
            CleanupLedger.shared.record(kind: kind, deletedIds: deletedIds, sizeOf: { sizeById[$0] ?? 0 })
            apply(deletedIds)
            return Outcome(removed: deletedIds, errorMessage: nil, deletedCount: deletedIds.count)
        } catch let error as PhotoServiceError {
            if let succeededIds = error.succeededIds {
                recordDeleted?(succeededIds.count)
                CleanupLedger.shared.record(kind: kind, deletedIds: succeededIds, sizeOf: { sizeById[$0] ?? 0 })
                apply(succeededIds)
                return Outcome(removed: succeededIds, errorMessage: error.localizedDescription, deletedCount: succeededIds.count)
            }
            return Outcome(removed: [], errorMessage: error.localizedDescription, deletedCount: nil)
        } catch {
            return Outcome(removed: [], errorMessage: error.localizedDescription, deletedCount: nil)
        }
    }
}
