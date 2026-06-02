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
        groups = burstGroups.map { (burstId, assets) in
            let sorted = assets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            // Best = favorited one, or highest resolution
            let best = sorted.first(where: \.isFavorite) ?? sorted.max { a, b in
                a.pixelWidth * a.pixelHeight < b.pixelWidth * b.pixelHeight
            } ?? sorted[0]
            return BurstGroup(id: burstId, assets: sorted, bestAssetId: best.id)
        }
        .sorted { $0.assets.count > $1.assets.count }

        selectNonBestFrames()

        hasLoadedGroups = true
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh spinner.
    func refresh() async {
        errorMessage = nil

        let burstGroups = await photoService.fetchBurstPhotos()
        groups = burstGroups.map { (burstId, assets) in
            let sorted = assets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            // Best = favorited one, or highest resolution
            let best = sorted.first(where: \.isFavorite) ?? sorted.max { a, b in
                a.pixelWidth * a.pixelHeight < b.pixelWidth * b.pixelHeight
            } ?? sorted[0]
            return BurstGroup(id: burstId, assets: sorted, bestAssetId: best.id)
        }
        .sorted { $0.assets.count > $1.assets.count }

        selectNonBestFrames()

        hasLoadedGroups = true
    }

    func toggleSelection(_ assetId: String) {
        selectedForDeletion.toggle(assetId)
    }

    func setBest(assetId: String, in groupId: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let oldBest = groups[index].bestAssetId
        guard oldBest != assetId else { return }
        groups[index].bestAssetId = assetId

        // Update selection
        selectedForDeletion.remove(assetId)
        selectedForDeletion.insert(oldBest)
    }

    func deleteSelected() async {
        guard !selectedForDeletion.isEmpty, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedForDeletion))
            let deleted = selectedForDeletion
            var collapsedToSingleFrame = 0
            groups = groups.compactMap { group in
                let remaining = group.assets.filter { !deleted.contains($0.id) }
                guard remaining.count > 1 else {
                    if remaining.count == 1 { collapsedToSingleFrame += 1 }
                    return nil
                }
                let bestAssetId = remaining.contains(where: { $0.id == group.bestAssetId })
                    ? group.bestAssetId
                    : preferredBestAsset(in: remaining).id
                return BurstGroup(id: group.id, assets: remaining, bestAssetId: bestAssetId)
            }
            // Bursts reduced to a single frame are no longer "bursts" and drop out
            // of the list; let the user know rather than having them silently vanish.
            if collapsedToSingleFrame > 0 {
                statusMessage = collapsedToSingleFrame == 1
                    ? "1 burst cleaned down to a single photo."
                    : "\(collapsedToSingleFrame) bursts cleaned down to single photos."
            }
            selectNonBestFrames()
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
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: [id])
            selectedForDeletion.remove(id)
            guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
            let remaining = groups[index].assets.filter { $0.id != id }
            if remaining.count > 1 {
                let bestAssetId = remaining.contains(where: { $0.id == groups[index].bestAssetId })
                    ? groups[index].bestAssetId
                    : preferredBestAsset(in: remaining).id
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

    private func selectNonBestFrames() {
        selectedForDeletion = Set(
            groups.flatMap { group in
                group.assets.compactMap { asset in
                    asset.id == group.bestAssetId ? nil : asset.id
                }
            }
        )
    }

    private func preferredBestAsset(in assets: [AssetSummary]) -> AssetSummary {
        assets.first(where: \.isFavorite) ?? assets.max { a, b in
            a.pixelWidth * a.pixelHeight < b.pixelWidth * b.pixelHeight
        } ?? assets[0]
    }
}
