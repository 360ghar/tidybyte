import SwiftUI

enum LargeFileFilter: String, CaseIterable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
}

enum LargeFileSortOrder: String, CaseIterable {
    case largest = "Largest"
    case newest = "Newest"
    case oldest = "Oldest"
    case filename = "Filename"
}

@Observable
@MainActor
final class LargeFilesViewModel {
    var assets: [AssetSummary] = []
    var isLoading = true
    private(set) var hasLoadedAssets = false
    var selectedIds: Set<String> = []
    var mediaFilter: LargeFileFilter = .all
    var sortOrder: LargeFileSortOrder = .largest
    var errorMessage: String?
    var isDeleting = false

    // Share/export state
    var isPreparingShare = false
    var shareProgress: (completed: Int, total: Int) = (0, 0)
    var sharePayload: SharePayload?
    private var shareTask: Task<Void, Never>?

    var thresholdMB: Double = AppPreferences.largeFileThresholdMB() {
        didSet { AppPreferences.saveLargeFileThresholdMB(thresholdMB) }
    }

    private let photoService = PhotoLibraryService()

    var thresholdBytes: Int64 {
        // Delegate to the shared helper so this stays in lockstep with any other
        // call site (e.g. the Storage dashboard's "Large Files" reclaim win).
        AppPreferences.largeFileThresholdBytes()
    }

    var filteredAssets: [AssetSummary] {
        var result = assets.filter { $0.fileSize >= thresholdBytes }
        switch mediaFilter {
        case .all: break
        case .photos: result = result.filter { $0.mediaType == .photo }
        case .videos: result = result.filter { $0.mediaType == .video }
        }
        switch sortOrder {
        case .largest:
            return result.sorted { $0.fileSize > $1.fileSize }
        case .newest:
            return result.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .oldest:
            return result.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .filename:
            return result.sorted {
                ($0.filename ?? "").localizedCaseInsensitiveCompare($1.filename ?? "") == .orderedAscending
            }
        }
    }

    var totalSize: Int64 {
        filteredAssets.reduce(0) { $0 + $1.fileSize }
    }

    var selectedSize: Int64 {
        filteredAssets.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }

    var selectedVisibleCount: Int {
        filteredAssets.filter { selectedIds.contains($0.id) }.count
    }

    var areAllVisibleSelected: Bool {
        !filteredAssets.isEmpty && selectedVisibleCount == filteredAssets.count
    }

    /// Currently-selected ids that are still visible under the active filters.
    var visibleSelectedIds: [String] {
        Array(Set(filteredAssets.map(\.id)).intersection(selectedIds))
    }

    func loadIfNeeded() async {
        guard !hasLoadedAssets else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        assets = allAssets.sorted { $0.fileSize > $1.fileSize }
        synchronizeSelection()
        hasLoadedAssets = true
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh
    /// spinner. Current `mediaFilter`/`sortOrder`/`thresholdMB` state is preserved.
    func refresh() async {
        errorMessage = nil
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        assets = allAssets.sorted { $0.fileSize > $1.fileSize }
        synchronizeSelection()
        hasLoadedAssets = true
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    func selectAll() {
        selectedIds = Set(filteredAssets.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func synchronizeSelection() {
        selectedIds.formIntersection(Set(filteredAssets.map(\.id)))
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        isDeleting = true
        do {
            let visibleSelectedIds = Set(filteredAssets.map(\.id)).intersection(selectedIds)
            try await photoService.deleteAssets(identifiers: Array(visibleSelectedIds))
            assets.removeAll { visibleSelectedIds.contains($0.id) }
            selectedIds.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }

    /// Deletes a single asset (used by the per-row trash button and the
    /// in-preview Delete action). Leaves selection mode untouched.
    func deleteAsset(id: String) async {
        guard !isDeleting else { return }
        isDeleting = true
        do {
            try await photoService.deleteAssets(identifiers: [id])
            assets.removeAll { $0.id == id }
            selectedIds.remove(id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }

    // MARK: - Share / Export

    /// Exports the visible selected assets to temp files and, when ready,
    /// publishes a `SharePayload` that the view presents in a share sheet.
    func startShare() {
        let ids = visibleSelectedIds
        guard !ids.isEmpty, !isPreparingShare else { return }
        isPreparingShare = true
        shareProgress = (0, ids.count)
        shareTask = Task { [weak self] in
            guard let self else { return }
            let urls = await self.photoService.exportAssetsForSharing(identifiers: ids) { [weak self] completed, total in
                self?.shareProgress = (completed, total)
            }
            self.isPreparingShare = false
            if Task.isCancelled {
                self.deleteExportFolder(for: urls)
                return
            }
            if urls.isEmpty {
                self.errorMessage = "Couldn't prepare the selected items to share."
            } else {
                self.sharePayload = SharePayload(urls: urls)
            }
        }
    }

    func cancelShare() {
        shareTask?.cancel()
        shareTask = nil
        isPreparingShare = false
    }

    /// Removes the temp export folder once the share sheet is dismissed.
    func cleanupShareExport() {
        if let payload = sharePayload {
            deleteExportFolder(for: payload.urls)
        }
        sharePayload = nil
    }

    private func deleteExportFolder(for urls: [URL]) {
        guard let folder = urls.first?.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
