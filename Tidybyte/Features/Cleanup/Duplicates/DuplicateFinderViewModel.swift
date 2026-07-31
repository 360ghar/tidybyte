import SwiftUI

enum ScanState: Equatable {
    case idle
    case scanning(Float)
    case completed
    case error(String)
}

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

    private let photoService = PhotoLibraryService()
    private let visionService = VisionAnalysisService()
    private let duplicateService: DuplicateDetectionService
    /// DUP-02: the scan is held in a cancellable task so leaving the screen or
    /// tapping Cancel actually stops it, and re-entry can be guarded.
    private var scanTask: Task<Void, Never>?

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

    var totalSavingsBytes: Int64 {
        allGroups.reduce(Int64(0)) { total, group in
            let nonBest = group.assets.filter { $0.id != group.bestAssetId }
            return total + nonBest.reduce(Int64(0)) { $0 + $1.fileSize }
        }
    }

    var selectedSavingsBytes: Int64 {
        allGroups.reduce(Int64(0)) { total, group in
            total + group.assets.filter { selectedForDeletion.contains($0.id) }
                .reduce(0) { subtotal, asset in subtotal + asset.fileSize }
        }
    }

    /// Every asset across every group is currently selected for deletion.
    var allSelectedForDeletion: Bool {
        let allIds = Set(allGroups.flatMap { $0.assets.map(\.id) })
        return !allIds.isEmpty && selectedForDeletion == allIds
    }

    // MARK: - Scan lifecycle (DUP-02)

    func startScan() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            await self?.scan()
            self?.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if case .scanning = scanState {
            scanState = .idle
        }
    }

    func scan() async {
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

        if Task.isCancelled {
            scanState = .idle
            return
        }

        if currentScanType == .exact || currentScanType == .all {
            let scale: Float = currentScanType == .all ? 0.5 : 1.0
            let result = await duplicateService.findExactDuplicates(assets: assets) { [weak self] progress in
                Task { @MainActor in
                    self?.scanState = .scanning(progress * scale)
                }
            }
            exactGroups = result.groups
            skippedICloudCount = result.skippedCount
            if Task.isCancelled {
                scanState = .idle
                return
            }
        }

        if currentScanType == .visual || currentScanType == .all {
            let startProgress: Float = currentScanType == .all ? 0.5 : 0
            let scale: Float = currentScanType == .all ? 0.5 : 1.0
            visualGroups = await duplicateService.findVisualDuplicates(assets: assets) { [weak self] progress in
                Task { @MainActor in
                    self?.scanState = .scanning(startProgress + progress * scale)
                }
            }
            if Task.isCancelled {
                scanState = .idle
                return
            }
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

        scanState = .completed

        selectNonBestAssets()
    }

    // MARK: - Deletion

    func deleteSelected() async {
        guard !selectedForDeletion.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedForDeletion))
            deletedCount = selectedForDeletion.count
            let deleted = selectedForDeletion
            exactGroups = normalizeGroups(exactGroups, removing: deleted)
            visualGroups = normalizeGroups(visualGroups, removing: deleted)
            selectNonBestAssets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// DUP-04a: delete just one group's non-best assets through the shared
    /// delete flow. On failure the previous selection is restored.
    func delete(group: DuplicateGroup) async {
        let ids = Self.nonBestAssetIds(in: group)
        guard !ids.isEmpty, !isDeleting else { return }
        let previousSelection = selectedForDeletion
        selectedForDeletion = ids
        await deleteSelected()
        if errorMessage != nil {
            selectedForDeletion = previousSelection
        }
    }

    // MARK: - Selection (DUP-04c)

    func selectAllForDeletion() {
        var state = SelectionState(ids: selectedForDeletion)
        state.selectAll(Set(allGroups.flatMap { $0.assets.map(\.id) }))
        selectedForDeletion = state.ids
    }

    func deselectAllForDeletion() {
        var state = SelectionState(ids: selectedForDeletion)
        state.deselectAll()
        selectedForDeletion = state.ids
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
