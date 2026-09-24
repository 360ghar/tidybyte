import SwiftUI

struct BurstGroup: Identifiable {
    let id: String
    let assets: [AssetSummary]
    var bestAssetId: String
}

@Observable
@MainActor
final class BurstCleanerViewModel {
    var groups: [BurstGroup] = []
    var isLoading = true
    private(set) var hasLoadedGroups = false
    var selectedForDeletion: Set<String> = []
    var errorMessage: String?
    var statusMessage: String?
    var isDeleting = false

    /// Group ids where the user explicitly picked a best frame via `setBest`.
    /// `refresh()` keeps those stored picks instead of recomputing them
    /// (LF-01); `BestAssetSelector` remains the fallback for untouched groups.
    private(set) var manuallySetBest: Set<String> = []

    /// Group ids where the user interacted (toggled selection or set best).
    /// `deleteSelected()`/`refresh()` only re-arm non-best frames for groups the
    /// user never touched, so explicit keep/deselect choices survive (LF-02).
    private(set) var touchedGroups: Set<String> = []

    private let photoService = PhotoLibraryService.shared

    var totalBurstCount: Int {
        groups.reduce(0) { $0 + $1.assets.count }
    }

    /// Frames Auto-Clean would delete: all but the keeper, never a favorite.
    var deletableCount: Int { autoCleanIds.count }

    var allNonBestSelected: Bool {
        let ids = groups.reduce(into: Set<String>()) { $0.formUnion(Self.nonBestAssetIds(in: $1)) }
        return !ids.isEmpty && ids.isSubset(of: selectedForDeletion)
    }

    /// Select All: every frame but the keepers (favorites included: this is an
    /// explicit choice). Counts as touching every group, so a refresh keeps it.
    func selectAllNonBest() {
        for group in groups { selectedForDeletion.formUnion(Self.nonBestAssetIds(in: group)) }
        touchedGroups.formUnion(groups.map(\.id))
    }

    func deselectAll() {
        selectedForDeletion.removeAll()
        touchedGroups.formUnion(groups.map(\.id))
    }

    var savingsBytes: Int64 {
        groups.reduce(Int64(0)) { total, group in
            let suggested = Self.suggestedIds(in: group)
            return group.assets.filter { suggested.contains($0.id) }
                .reduce(total) { $0 + $1.fileSize }
        }
    }

    var selectedSavingsBytes: Int64 {
        groups.reduce(Int64(0)) { total, group in
            total + group.assets.filter { selectedForDeletion.contains($0.id) }
                .reduce(0) { subtotal, asset in subtotal + asset.fileSize }
        }
    }

    var selectedCount: Int {
        selectedForDeletion.count
    }

    func loadIfNeeded() async {
        guard !hasLoadedGroups else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        let burstGroups = await photoService.fetchBurstPhotos()
        apply(Self.rebuildGroups(from: burstGroups), preservingUserState: false)

        hasLoadedGroups = true
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh
    /// spinner. User best picks and explicit selection choices are preserved (LF-01).
    func refresh() async {
        errorMessage = nil

        let burstGroups = await photoService.fetchBurstPhotos()
        apply(Self.rebuildGroups(from: burstGroups), preservingUserState: true)

        hasLoadedGroups = true
    }

    /// Shared load/refresh pipeline (de-slop D3). On a fresh load, non-best
    /// frames are pre-selected. On a refresh, selection is merged against the
    /// previous state so explicit deselects/selects survive (LF-01).
    private func apply(_ newGroups: [BurstGroup], preservingUserState: Bool) {
        guard preservingUserState else {
            groups = newGroups
            selectNonBestFrames()
            return
        }
        let oldGroups = groups
        let oldGroupIds = Set(oldGroups.map(\.id))
        let oldSelection = selectedForDeletion
        groups = Self.preservingManualBests(in: newGroups, oldGroups: oldGroups, manuallySetBest: manuallySetBest)
        let survivingIds = Set(groups.flatMap { $0.assets.map(\.id) })
        // Groups that just appeared get the default treatment; everything else
        // keeps exactly what the user chose.
        let newlyAppearedIds = Set(newGroups.map(\.id)).subtracting(oldGroupIds)
        selectedForDeletion = Self.mergedSelection(
            oldSelection: oldSelection,
            survivingIds: survivingIds,
            touchedGroups: touchedGroups.subtracting(newlyAppearedIds),
            groups: groups
        )
    }

    func toggleSelection(_ assetId: String) {
        selectedForDeletion.toggle(assetId)
        if let group = groups.first(where: { $0.assets.contains(where: { $0.id == assetId }) }) {
            touchedGroups.insert(group.id)
        }
    }

    /// Marks the frame as the group's best. The previous best is *not*
    /// force-inserted into the deletion set: if the user explicitly deselected
    /// it (or never armed it) it stays kept (LF-12). The new best is always
    /// removed from the deletion set.
    func setBest(assetId: String, in groupId: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let oldBest = groups[index].bestAssetId
        guard oldBest != assetId else { return }
        groups[index].bestAssetId = assetId
        manuallySetBest.insert(groupId)
        touchedGroups.insert(groupId)

        selectedForDeletion.remove(assetId)
        // oldBest stays in (or out of) the selection exactly as the user left it.
    }

    func deleteSelected() async {
        guard !selectedForDeletion.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        // D7: capture BOTH the deleted set and the user's selection BEFORE the
        // await. Snapshotting after the delete let toggles made during the
        // deletion window be treated as deleted — frames vanished from the UI
        // while still existing in the library.
        let deleted = selectedForDeletion
        let oldSelection = selectedForDeletion
        // Sizes captured before the await (the frames are gone afterwards).
        let sizeById = groups.reduce(into: [String: Int64]()) { result, group in
            for asset in group.assets { result[asset.id] = asset.fileSize }
        }
        let outcome = await CleanupDeletion.delete(
            requestedIds: deleted,
            kind: .bursts,
            sizeById: sizeById,
            apply: { applyPostDeleteState(removed: $0, previousSelection: oldSelection) }
        )
        errorMessage = outcome.errorMessage
    }

    /// Shared post-delete pipeline: collapses groups, re-picks keepers, and
    /// merges the surviving selection (used by both full success and partial
    /// failure so the UI state matches the library in every path).
    private func applyPostDeleteState(removed: Set<String>, previousSelection: Set<String>) {
        var collapsedToSingleFrame = 0
        groups = groups.compactMap { group in
            let remaining = group.assets.filter { !removed.contains($0.id) }
            guard remaining.count > 1 else {
                if remaining.count == 1 { collapsedToSingleFrame += 1 }
                manuallySetBest.remove(group.id)
                return nil
            }
            let bestAssetId: String
            if remaining.contains(where: { $0.id == group.bestAssetId }) {
                bestAssetId = group.bestAssetId
            } else {
                // The manually picked frame left the group: the fallback
                // re-pick is automatic, so drop the "your choice" flag.
                manuallySetBest.remove(group.id)
                guard let newBest = BestAssetSelector.bestByMetadata(from: remaining) else {
                    return nil
                }
                bestAssetId = newBest.id
            }
            return BurstGroup(id: group.id, assets: remaining, bestAssetId: bestAssetId)
        }
        // Bursts reduced to a single frame are no longer "bursts" and drop out
        // of the list; let the user know rather than having them silently vanish.
        if collapsedToSingleFrame > 0 {
            statusMessage = collapsedToSingleFrame == 1
                ? "1 burst cleaned down to a single photo."
                : "\(collapsedToSingleFrame) bursts cleaned down to single photos."
        }
        // LF-02: never blanket re-select. Untouched groups get all non-best
        // re-armed; touched groups keep exactly the user's surviving choices.
        let survivingIds = Set(groups.flatMap { $0.assets.map(\.id) })
        selectedForDeletion = Self.mergedSelection(
            oldSelection: previousSelection,
            survivingIds: survivingIds,
            touchedGroups: touchedGroups,
            groups: groups
        )
    }

    /// Exactly what Auto-Clean deletes: in every burst, all frames but the
    /// starred keeper, never a favorite. The confirm count, the delete and the
    /// celebration all use this one set, so they cannot disagree.
    var autoCleanIds: Set<String> {
        groups.reduce(into: Set<String>()) { $0.formUnion(Self.suggestedIds(in: $1)) }
    }

    /// Exactly what Auto-Clean arms: untouched groups contribute their
    /// suggestions; touched groups contribute only the user's surviving picks,
    /// so a frame the user explicitly kept is never re-armed. Pure for tests.
    static func autoCleanArmedIds(
        groups: [BurstGroup],
        touchedGroups: Set<String>,
        selection: Set<String>
    ) -> Set<String> {
        groups.reduce(into: Set<String>()) { armed, group in
            if touchedGroups.contains(group.id) {
                armed.formUnion(selection.intersection(group.assets.map(\.id)))
            } else {
                armed.formUnion(Self.suggestedIds(in: group))
            }
        }
    }

    /// Deletes `autoCleanIds` through the shared pipeline. Returns how many
    /// frames really left the library (0 on a decline or a failure).
    @discardableResult
    func autoCleanAll() async -> Int {
        let previousSelection = selectedForDeletion
        let armed = Self.autoCleanArmedIds(
            groups: groups,
            touchedGroups: touchedGroups,
            selection: previousSelection
        )
        guard !armed.isEmpty else { return 0 }
        selectedForDeletion = armed
        await deleteSelected()
        let survivors = Set(groups.flatMap { $0.assets.map(\.id) })
        let removed = armed.subtracting(survivors).count
        if removed == 0 {
            selectedForDeletion = previousSelection.intersection(survivors)
        }
        return removed
    }

    /// Deletes a single burst frame (used by the in-preview Delete action),
    /// rebuilding its group and dropping the group if it collapses to a single
    /// frame. Other groups' selections are left untouched.
    func deleteAsset(id: String, fromGroup groupId: String) async -> Bool {
        guard !isDeleting else { return !groups.contains(where: { $0.assets.contains(where: { $0.id == id }) }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        let sizeById = groups.reduce(into: [String: Int64]()) { result, group in
            for asset in group.assets { result[asset.id] = asset.fileSize }
        }
        let outcome = await CleanupDeletion.delete(
            requestedIds: [id],
            kind: .bursts,
            sizeById: sizeById,
            apply: { deletedIds in
                guard deletedIds.contains(id) else { return }
                selectedForDeletion.remove(id)
                guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
                let remaining = groups[index].assets.filter { $0.id != id }
                if remaining.count > 1 {
                    let bestAssetId: String
                    if remaining.contains(where: { $0.id == groups[index].bestAssetId }) {
                        bestAssetId = groups[index].bestAssetId
                    } else if let newBest = BestAssetSelector.bestByMetadata(from: remaining) {
                        // The manually picked frame was deleted: the fallback
                        // re-pick is automatic, so drop the "your choice" flag.
                        manuallySetBest.remove(groupId)
                        bestAssetId = newBest.id
                    } else {
                        return
                    }
                    groups[index] = BurstGroup(id: groupId, assets: remaining, bestAssetId: bestAssetId)
                } else {
                    // No longer a burst once it's down to one frame — drop the group.
                    for asset in remaining { selectedForDeletion.remove(asset.id) }
                    manuallySetBest.remove(groupId)
                    groups.remove(at: index)
                }
            }
        )
        errorMessage = outcome.errorMessage
        return !groups.contains(where: { $0.assets.contains(where: { $0.id == id }) })
    }

    // MARK: - Selection helpers

    private func selectNonBestFrames() {
        selectedForDeletion = groups.reduce(into: Set<String>()) { result, group in
            result.formUnion(Self.suggestedIds(in: group))
        }
    }

    /// Merges a previous selection into the current survivor set (LF-01/LF-02):
    /// the user's explicit picks survive by intersection, and non-best frames
    /// are (re-)armed only for groups the user never interacted with.
    static func mergedSelection(
        oldSelection: Set<String>,
        survivingIds: Set<String>,
        touchedGroups: Set<String>,
        groups: [BurstGroup]
    ) -> Set<String> {
        var merged = oldSelection.intersection(survivingIds)
        for group in groups where !touchedGroups.contains(group.id) {
            merged.formUnion(suggestedIds(in: group))
        }
        return merged
    }

    /// Carries a user's manually-set best frames across a refresh, as long as
    /// the picked frame still exists in the freshly-fetched group (LF-01).
    static func preservingManualBests(
        in newGroups: [BurstGroup],
        oldGroups: [BurstGroup],
        manuallySetBest: Set<String>
    ) -> [BurstGroup] {
        newGroups.map { group in
            guard manuallySetBest.contains(group.id),
                  let oldBest = oldGroups.first(where: { $0.id == group.id })?.bestAssetId,
                  group.assets.contains(where: { $0.id == oldBest })
            else { return group }
            return BurstGroup(id: group.id, assets: group.assets, bestAssetId: oldBest)
        }
    }

    /// Sorts each burst bin by capture time and computes the best frame
    /// (via the shared `BestAssetSelector` ladder — D14: the previous local
    /// duplicate used a different, non-deterministic-on-ties order), skipping
    /// empty bins (LF-13).
    static func rebuildGroups(from burstGroups: [String: [AssetSummary]]) -> [BurstGroup] {
        var result: [BurstGroup] = []
        for (burstId, assets) in burstGroups {
            let sorted = assets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            guard let best = BestAssetSelector.bestByMetadata(from: sorted) else { continue }
            result.append(BurstGroup(id: burstId, assets: sorted, bestAssetId: best.id))
        }
        return result.sorted { $0.assets.count > $1.assets.count }
    }

    /// What the tool arms by itself: every frame but the keeper, except
    /// favorites. A favorite is only deleted when the user marks it.
    static func suggestedIds(in group: BurstGroup) -> Set<String> {
        Set(group.assets.compactMap { $0.id == group.bestAssetId || $0.isFavorite ? nil : $0.id })
    }

    private static func nonBestAssetIds(in group: BurstGroup) -> Set<String> {
        Set(group.assets.compactMap { $0.id == group.bestAssetId ? nil : $0.id })
    }
}
