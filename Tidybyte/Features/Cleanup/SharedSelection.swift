import Foundation

/// Shared "mark for deletion" selection rules for the Duplicates and Similar
/// Photos tools (de-slop: both finder view models previously duplicated this
/// logic). A small value type over `Set<String>` — the view models keep their
/// public `selectedForDeletion` set (pinned by tests and used in SwiftUI
/// bindings) and funnel every mutation through this helper so the two tools
/// behave identically. Bursts keeps its own selection flow but shares
/// `selectNonBest`.
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
    ///
    /// The previous best is marked only when the group already had something
    /// checked, and never when it is a favorite. Groups that start with nothing
    /// selected (similar shots) stay unselected, and a favorite is only marked
    /// by the user's own tap.
    mutating func setBest(newBest: String, oldBest: String, groupAssets: [AssetSummary]) {
        guard newBest != oldBest else { return }
        let groupWasSelecting = groupAssets.contains { ids.contains($0.id) }
        let oldBestIsFavorite = groupAssets.first { $0.id == oldBest }?.isFavorite ?? false
        ids.remove(newBest)
        if groupWasSelecting && !oldBestIsFavorite {
            ids.insert(oldBest)
        }
    }

    /// Suggested selection: every non-best asset across groups, except
    /// favorites. A favorite is never marked for deletion unless the user
    /// taps it.
    mutating func selectNonBest(assets: [AssetSummary], bestAssetId: String) {
        for asset in assets where asset.id != bestAssetId && !asset.isFavorite {
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
