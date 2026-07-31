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
    /// (LF-01); `preferredBestAsset` remains the fallback for untouched groups.
    private(set) var manuallySetBest: Set<String> = []

    /// Group ids where the user interacted (toggled selection or set best).
    /// `deleteSelected()`/`refresh()` only re-arm non-best frames for groups the
    /// user never touched, so explicit keep/deselect choices survive (LF-02).
    private(set) var touchedGroups: Set<String> = []

    private let photoService = PhotoLibraryService()

    var totalBurstCount: Int {
        groups.reduce(0) { $0 + $1.assets.count }
    }

    var deletableCount: Int {
        groups.reduce(0) { $0 + $1.assets.count - 1 }
    }

    var savingsBytes: Int64 {
        groups.reduce(Int64(0)) { total, group in
            group.assets.filter { $0.id != group.bestAssetId }
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
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedForDeletion))
            let deleted = selectedForDeletion
            let oldSelection = selectedForDeletion
            var collapsedToSingleFrame = 0
            groups = groups.compactMap { group in
                let remaining = group.assets.filter { !deleted.contains($0.id) }
                guard remaining.count > 1 else {
                    if remaining.count == 1 { collapsedToSingleFrame += 1 }
                    return nil
                }
                let bestAssetId: String
                if remaining.contains(where: { $0.id == group.bestAssetId }) {
                    bestAssetId = group.bestAssetId
                } else if let newBest = Self.preferredBestAsset(in: remaining) {
                    bestAssetId = newBest.id
                } else {
                    return nil
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
                oldSelection: oldSelection,
                survivingIds: survivingIds,
                touchedGroups: touchedGroups,
                groups: groups
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func autoCleanAll() async {
        // Select all non-best from every group
        selectNonBestFrames()
        await deleteSelected()
    }

    /// Deletes a single burst frame (used by the in-preview Delete action),
    /// rebuilding its group and dropping the group if it collapses to a single
    /// frame. Other groups' selections are left untouched.
    func deleteAsset(id: String, fromGroup groupId: String) async {
        guard !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: [id])
            selectedForDeletion.remove(id)
            guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
            let remaining = groups[index].assets.filter { $0.id != id }
            if remaining.count > 1 {
                let bestAssetId: String
                if remaining.contains(where: { $0.id == groups[index].bestAssetId }) {
                    bestAssetId = groups[index].bestAssetId
                } else if let newBest = Self.preferredBestAsset(in: remaining) {
                    bestAssetId = newBest.id
                } else {
                    return
                }
                groups[index] = BurstGroup(id: groupId, assets: remaining, bestAssetId: bestAssetId)
            } else {
                // No longer a burst once it's down to one frame — drop the group.
                for asset in remaining { selectedForDeletion.remove(asset.id) }
                groups.remove(at: index)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Selection helpers

    private func selectNonBestFrames() {
        selectedForDeletion = groups.reduce(into: Set<String>()) { result, group in
            result.formUnion(Self.nonBestAssetIds(in: group))
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
            merged.formUnion(nonBestAssetIds(in: group))
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
    /// (favorite → highest resolution → first), skipping empty bins (LF-13).
    static func rebuildGroups(from burstGroups: [String: [AssetSummary]]) -> [BurstGroup] {
        var result: [BurstGroup] = []
        for (burstId, assets) in burstGroups {
            let sorted = assets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            guard let best = preferredBestAsset(in: sorted) else { continue }
            result.append(BurstGroup(id: burstId, assets: sorted, bestAssetId: best.id))
        }
        return result.sorted { $0.assets.count > $1.assets.count }
    }

    /// Best = favorited one, or highest resolution, or first (de-slop D2;
    /// the shared fallback used by load/refresh/rebuild).
    private static func preferredBestAsset(in assets: [AssetSummary]) -> AssetSummary? {
        assets.first(where: \.isFavorite)
            ?? assets.max { a, b in
                a.pixelWidth * a.pixelHeight < b.pixelWidth * b.pixelHeight
            }
            ?? assets.first
    }

    private static func nonBestAssetIds(in group: BurstGroup) -> Set<String> {
        Set(group.assets.compactMap { $0.id == group.bestAssetId ? nil : $0.id })
    }
}
