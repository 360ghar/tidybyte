import Foundation

/// Shared "mark for deletion" selection rules for the Duplicates and Similar
/// Photos tools (de-slop: both finder view models previously duplicated this
/// logic). A small value type over `Set<String>` — the view models keep their
/// public `selectedForDeletion` set (pinned by tests and used in SwiftUI
/// bindings) and funnel every mutation through this helper so the two tools
/// behave identically. Bursts intentionally keeps its own copy.
struct SelectionState {
    private(set) var ids: Set<String> = []

    init(ids: Set<String> = []) {
        self.ids = ids
    }

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    mutating func toggle(_ id: String) {
        ids.toggle(id)
    }

    /// After a group's best asset changes, the new best leaves the deletion set
    /// and the previous best enters it — "delete everything but one per group"
    /// stays true without manual bookkeeping. Re-selecting the same best is a
    /// no-op.
    mutating func setBest(newBest: String, oldBest: String) {
        guard newBest != oldBest else { return }
        ids.remove(newBest)
        ids.insert(oldBest)
    }

    /// Default selection after a scan or delete: every non-best asset across
    /// groups.
    mutating func selectNonBest(assets: [AssetSummary], bestAssetId: String) {
        for asset in assets where asset.id != bestAssetId {
            ids.insert(asset.id)
        }
    }

    mutating func selectAll(_ allIds: Set<String>) {
        ids = allIds
    }

    mutating func deselectAll() {
        ids.removeAll()
    }
}
