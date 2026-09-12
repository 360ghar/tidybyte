import SwiftUI
import SwiftData

/// Loads the cleanup ledger and folds it into the pure `CleanupActivitySummary`
/// the Activity screen renders. Reconciliation (and the cached-totals write the
/// widget and `FreeSpaceIntent` read) lives in `CleanupLedger`, so this screen
/// and those surfaces cannot compute savings two different ways.
@Observable
@MainActor
final class ActivityViewModel {
    var summary = CleanupActivitySummary()
    var isLoading = true

    private var hasLoaded = false
    private var syncedGeneration = Int.min

    /// Generation-aware entry point, mirroring `StorageDashboardViewModel`:
    /// loads on first call, refreshes when the library generation advances
    /// (a cleanup just happened), and no-ops otherwise.
    func sync(to generation: Int, modelContext: ModelContext) {
        guard !(hasLoaded && generation == syncedGeneration) else { return }
        syncedGeneration = generation
        reload(modelContext: modelContext)
        hasLoaded = true
        isLoading = false
    }

    func refresh(modelContext: ModelContext) {
        reload(modelContext: modelContext)
    }

    /// One fetch through the shared ledger rather than a second copy of the
    /// query + cache-write logic (which could have drifted from the widget's
    /// numbers). `refreshCache` logs its own failures and returns an empty
    /// summary, so there is no error path to handle here.
    func reload(modelContext: ModelContext) {
        summary = CleanupLedger.shared.refreshCache(modelContext: modelContext)
    }
}
