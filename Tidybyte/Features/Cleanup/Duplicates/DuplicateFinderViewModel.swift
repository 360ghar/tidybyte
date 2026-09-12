import SwiftUI

@Observable
@MainActor
final class DuplicateFinderViewModel {
    var exactGroups: [DuplicateGroup] = []
    var visualGroups: [DuplicateGroup] = []
    var scanState: ScanState = .idle
    var selectedForDeletion: Set<String> = []
    var scanType: DuplicateScanType = .exact
    var errorMessage: String?
    var isDeleting = false
    /// DUP-03: exact scans skip iCloud-only assets (hashing would download
    /// them); the count is surfaced so the UI can explain why they're absent.
    var skippedICloudCount = 0
    /// DUP-04: how many items the last delete actually removed, so the view can
    /// gate the success haptic on a non-zero result (no more "Delete 0 Items").
    var deletedCount = 0

    private let photoService = PhotoLibraryService.shared
    private let visionService = VisionAnalysisService()
    private let duplicateService: DuplicateDetectionService
    /// C1/C2: owns the cancellable scan task + generation token.
    private let scanRunner = ScanRunner()

    init() {
        duplicateService = DuplicateDetectionService(
            photoService: photoService,
            visionService: visionService
        )
    }

    var allGroups: [DuplicateGroup] {
        switch scanType {
        case .exact: return exactGroups
        case .visual: return visualGroups
        case .all: return exactGroups + visualGroups
        }
    }

    var totalDuplicateCount: Int {
        allGroups.reduce(0) { $0 + $1.assets.count - 1 }
    }

    var selectedSavingsBytes: Int64 {
        allGroups.reduce(Int64(0)) { total, group in
            total + group.assets.filter { selectedForDeletion.contains($0.id) }
                .reduce(0) { subtotal, asset in subtotal + asset.fileSize }
        }
    }

    /// Every non-best asset across every group is selected (keepers excluded —
    /// one confirmation must never be able to delete every copy of a photo, C7).
    var allSelectedForDeletion: Bool {
        let allDeletableIds = Set(allGroups.flatMap { Self.nonBestAssetIds(in: $0) })
        return !allDeletableIds.isEmpty && selectedForDeletion == allDeletableIds
    }

    // MARK: - Scan lifecycle (DUP-02/C1)

    func startScan() {
        scanRunner.start { [weak self] token in
            await self?.scan(token: token)
        }
    }

    func cancelScan() {
        scanRunner.cancel()
        if case .scanning = scanState {
            scanState = .idle
        }
    }

    private func scan(token: Int) async {
        // A run whose token is already stale (cancelled before this body got a
        // turn on the main actor) must not touch shared state: `cancelScan()`
        // already moved the UI to `.idle`.
        guard scanRunner.isCurrent(token) else { return }
        scanState = .scanning(0)
        selectedForDeletion.removeAll()
        errorMessage = nil
        skippedICloudCount = 0
        deletedCount = 0

        // Capture the scan type once so progress math stays consistent even if the
        // view model is deallocated mid-scan (the @Sendable closures would otherwise
        // read self?.scanType and silently default to the wrong multiplier).
        let currentScanType = scanType
        let assets = await photoService.fetchAssets(filter: .allMedia)

        // A cancelled scan leaves the state alone: `cancelScan()` already moved
        // the UI to `.idle`, and writing it here would stomp a scan the user
        // restarted while this one was still unwinding (C1/C2).
        if Task.isCancelled { return }

        if currentScanType == .exact || currentScanType == .all {
            let scale: Float = currentScanType == .all ? 0.5 : 1.0
            let result = await duplicateService.findExactDuplicates(assets: assets) { [weak self] progress in
                Task { @MainActor in
                    // C2: dropped when the scan is no longer current.
                    self?.scanRunner.update(token) { self?.scanState = .scanning(progress * scale) }
                }
            }
            guard !Task.isCancelled else { return }
            exactGroups = result.groups
            skippedICloudCount = result.skippedCount
        }

        if currentScanType == .visual || currentScanType == .all {
            let startProgress: Float = currentScanType == .all ? 0.5 : 0
            let scale: Float = currentScanType == .all ? 0.5 : 1.0
            let foundVisualGroups = await duplicateService.findVisualDuplicates(assets: assets) { [weak self] progress in
                Task { @MainActor in
                    self?.scanRunner.update(token) { self?.scanState = .scanning(startProgress + progress * scale) }
                }
            }
            guard !Task.isCancelled else { return }
            visualGroups = foundVisualGroups
        }

        // DUP-07: exact groups are authoritative — an asset already claimed by an
        // exact group is dropped from visual groups so `.all` totals don't
        // double-count the same photo.
        if currentScanType == .all {
            visualGroups = Self.deduplicateVisualGroups(
                exactGroups: exactGroups,
                visualGroups: visualGroups
            )
        }

        // A cancelled or superseded run must never publish results: the user may
        // have restarted the scan (and switched scan type) while this one was
        // still unwinding, and publishing would pair these groups with the new
        // type's empty list.
        guard !Task.isCancelled, scanRunner.isCurrent(token) else { return }

        scanState = .completed

        selectNonBestAssets()
    }

    // MARK: - Deletion

    func deleteSelected() async {
        guard !selectedForDeletion.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        // Freed bytes must be attributed from the pre-delete metadata — the
        // assets are gone from the library once the delete returns.
        let sizeById = allGroups.reduce(into: [String: Int64]()) { result, group in
            for asset in group.assets { result[asset.id] = asset.fileSize }
        }
        let outcome = await CleanupDeletion.delete(
            requestedIds: selectedForDeletion,
            kind: .duplicates,
            sizeById: sizeById,
            apply: { applyDeletion(of: $0) },
            recordDeleted: { self.deletedCount = $0 }
        )
        errorMessage = outcome.errorMessage
    }

    /// DUP-04a: delete just one group's non-best assets through the shared
    /// delete flow. `applyDeletion` collapses the selection to this group's
    /// survivors, so the user's other selections are layered back on here —
    /// restricted to assets that still exist, because a partial failure means
    /// the rest of this group's ids really were deleted (re-arming them would
    /// leave ghosts that inflate counts and report as deleted a second time).
    func delete(group: DuplicateGroup) async {
        let ids = Self.nonBestAssetIds(in: group)
        guard !ids.isEmpty, !isDeleting else { return }
        let previousSelection = selectedForDeletion
        selectedForDeletion = ids
        await deleteSelected()
        let survivors = Set(allGroups.flatMap { $0.assets.map(\.id) })
        selectedForDeletion.formUnion(previousSelection.intersection(survivors))
    }

    /// Removes deleted ids from both group lists (collapsing groups below two
    /// members), then restores the selection to the surviving non-best assets —
    /// WITHOUT re-arming assets the user explicitly deselected (C6).
    private func applyDeletion(of deletedIds: Set<String>) {
        exactGroups = normalizeGroups(exactGroups, removing: deletedIds)
        visualGroups = normalizeGroups(visualGroups, removing: deletedIds)
        // C6: intersect with survivors instead of recomputing select-all-non-best,
        // so explicit keep-deselections survive the delete round-trip.
        selectedForDeletion.formIntersection(Set(allGroups.flatMap { $0.assets.map(\.id) }))
    }

    // MARK: - Selection (DUP-04c)

    /// Select All targets only the non-best assets (C7): keepers are never
    /// selected, so a single confirmation can never wipe out every copy.
    func selectAllForDeletion() {
        selectedForDeletion = Set(allGroups.flatMap { Self.nonBestAssetIds(in: $0) })
    }

    func deselectAllForDeletion() {
        selectedForDeletion.removeAll()
    }

    func toggleSelection(_ assetId: String) {
        var state = SelectionState(ids: selectedForDeletion)
        state.toggle(assetId)
        selectedForDeletion = state.ids
    }

    func setBest(assetId: String, in groupId: String) {
        if let exactIndex = exactGroups.firstIndex(where: { $0.id == groupId }) {
            let oldBest = exactGroups[exactIndex].bestAssetId
            exactGroups[exactIndex] = DuplicateGroup(
                id: exactGroups[exactIndex].id,
                assets: exactGroups[exactIndex].assets,
                bestAssetId: assetId,
                type: exactGroups[exactIndex].type
            )
            var state = SelectionState(ids: selectedForDeletion)
            state.setBest(newBest: assetId, oldBest: oldBest)
            selectedForDeletion = state.ids
            return
        }

        if let visualIndex = visualGroups.firstIndex(where: { $0.id == groupId }) {
            let oldBest = visualGroups[visualIndex].bestAssetId
            visualGroups[visualIndex] = DuplicateGroup(
                id: visualGroups[visualIndex].id,
                assets: visualGroups[visualIndex].assets,
                bestAssetId: assetId,
                type: visualGroups[visualIndex].type
            )
            var state = SelectionState(ids: selectedForDeletion)
            state.setBest(newBest: assetId, oldBest: oldBest)
            selectedForDeletion = state.ids
        }
    }

    // MARK: - Helpers

    /// The asset ids a group-scoped delete targets (everything but the keeper).
    static func nonBestAssetIds(in group: DuplicateGroup) -> Set<String> {
        Set(group.assets.filter { $0.id != group.bestAssetId }.map(\.id))
    }

    /// DUP-07: exact groups are authoritative — assets already claimed by an
    /// exact group are dropped from visual groups so `.all` results don't
    /// double-count. Visual groups that shrink below two members collapse, and
    /// the keeper is re-picked via BestAssetSelector when the old one was
    /// claimed by an exact group.
    static func deduplicateVisualGroups(
        exactGroups: [DuplicateGroup],
        visualGroups: [DuplicateGroup]
    ) -> [DuplicateGroup] {
        let claimed = Set(exactGroups.flatMap { $0.assets.map(\.id) })
        guard !claimed.isEmpty else { return visualGroups }
        return visualGroups.compactMap { group in
            let remaining = group.assets.filter { !claimed.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            let bestAssetId = remaining.contains(where: { $0.id == group.bestAssetId })
                ? group.bestAssetId
                : (BestAssetSelector.bestByMetadata(from: remaining) ?? remaining[0]).id
            return DuplicateGroup(
                id: group.id,
                assets: remaining,
                bestAssetId: bestAssetId,
                type: group.type
            )
        }
    }

    private func selectNonBestAssets() {
        var state = SelectionState()
        for group in allGroups {
            state.selectNonBest(assets: group.assets, bestAssetId: group.bestAssetId)
        }
        selectedForDeletion = state.ids
    }

    private func normalizeGroups(_ groups: [DuplicateGroup], removing deleted: Set<String>) -> [DuplicateGroup] {
        groups.compactMap { group in
            let remaining = group.assets.filter { !deleted.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            // DUP-10: re-pick the keeper through the shared BestAssetSelector
            // instead of the local duplicate ladder (removed).
            let bestAssetId = remaining.contains(where: { $0.id == group.bestAssetId })
                ? group.bestAssetId
                : (BestAssetSelector.bestByMetadata(from: remaining) ?? remaining[0]).id
            return DuplicateGroup(
                id: group.id,
                assets: remaining,
                bestAssetId: bestAssetId,
                type: group.type
            )
        }
    }
}

enum DuplicateScanType: String, CaseIterable {
    case exact = "Exact"
    case visual = "Visual"
    case all = "All"
}
