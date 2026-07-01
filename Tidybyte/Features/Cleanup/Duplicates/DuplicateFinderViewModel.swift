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

    private let photoService = PhotoLibraryService()
    private let visionService = VisionAnalysisService()
    private let duplicateService: DuplicateDetectionService

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

    func scan() async {
        scanState = .scanning(0)
        selectedForDeletion.removeAll()
        errorMessage = nil

        // Capture the scan type once so progress math stays consistent even if the
        // view model is deallocated mid-scan (the @Sendable closures would otherwise
        // read self?.scanType and silently default to the wrong multiplier).
        let currentScanType = scanType
        let assets = await photoService.fetchAssets(filter: .allMedia)

        if currentScanType == .exact || currentScanType == .all {
            let scale: Float = currentScanType == .all ? 0.5 : 1.0
            exactGroups = await duplicateService.findExactDuplicates(assets: assets) { [weak self] progress in
                Task { @MainActor in
                    self?.scanState = .scanning(progress * scale)
                }
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
        }

        // A cancelled scan returns partial/empty groups; don't present them as a
        // finished result (which would read as "No Duplicates Found").
        if Task.isCancelled {
            scanState = .idle
            return
        }

        scanState = .completed

        selectNonBestAssets()
    }

    func deleteSelected() async {
        guard !selectedForDeletion.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedForDeletion))
            let deleted = selectedForDeletion
            exactGroups = normalizeGroups(exactGroups, removing: deleted)
            visualGroups = normalizeGroups(visualGroups, removing: deleted)
            selectNonBestAssets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(_ assetId: String) {
        selectedForDeletion.toggle(assetId)
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
            selectedForDeletion.remove(assetId)
            if oldBest != assetId {
                selectedForDeletion.insert(oldBest)
            }
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
            selectedForDeletion.remove(assetId)
            if oldBest != assetId {
                selectedForDeletion.insert(oldBest)
            }
        }
    }

    private func selectNonBestAssets() {
        selectedForDeletion = Set(
            allGroups.flatMap { group in
                group.assets.compactMap { asset in
                    asset.id == group.bestAssetId ? nil : asset.id
                }
            }
        )
    }

    private func normalizeGroups(_ groups: [DuplicateGroup], removing deleted: Set<String>) -> [DuplicateGroup] {
        groups.compactMap { group in
            let remaining = group.assets.filter { !deleted.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            let bestAssetId = remaining.contains(where: { $0.id == group.bestAssetId })
                ? group.bestAssetId
                : preferredBestAsset(in: remaining).id
            return DuplicateGroup(
                id: group.id,
                assets: remaining,
                bestAssetId: bestAssetId,
                type: group.type
            )
        }
    }

    private func preferredBestAsset(in assets: [AssetSummary]) -> AssetSummary {
        assets.max { a, b in
            let aResolution = a.pixelWidth * a.pixelHeight
            let bResolution = b.pixelWidth * b.pixelHeight
            if aResolution != bResolution { return aResolution < bResolution }
            let aModified = a.modificationDate ?? .distantPast
            let bModified = b.modificationDate ?? .distantPast
            return aModified < bModified
        } ?? assets[0]
    }
}

enum DuplicateScanType: String, CaseIterable {
    case exact = "Exact"
    case visual = "Visual"
    case all = "All"
}
