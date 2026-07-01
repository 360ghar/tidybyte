import SwiftUI

enum ScreenshotSortOrder: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case largest = "Largest"
}

@Observable
@MainActor
final class ScreenshotCleanerViewModel {
    var screenshots: [AssetSummary] = []
    var isLoading = true
    private(set) var hasLoadedScreenshots = false
    var selectedIds: Set<String> = []
    var sortOrder: ScreenshotSortOrder = .newest
    var errorMessage: String?
    var isDeleting = false

    private let photoService = PhotoLibraryService()

    var totalSize: Int64 {
        screenshots.reduce(0) { $0 + $1.fileSize }
    }

    var selectedSize: Int64 {
        screenshots.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }

    var sortedScreenshots: [AssetSummary] {
        switch sortOrder {
        case .newest:
            return screenshots.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .oldest:
            return screenshots.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .largest:
            return screenshots.sorted { $0.fileSize > $1.fileSize }
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedScreenshots else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        screenshots = await photoService.fetchScreenshots()
        hasLoadedScreenshots = true
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh spinner.
    func refresh() async {
        errorMessage = nil
        screenshots = await photoService.fetchScreenshots()
        hasLoadedScreenshots = true
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    func selectAll() {
        selectedIds = Set(sortedScreenshots.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedIds))
            screenshots.removeAll { selectedIds.contains($0.id) }
            selectedIds.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(assetId: String) async {
        guard !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: [assetId])
            screenshots.removeAll { $0.id == assetId }
            selectedIds.remove(assetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
