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

    /// The in-flight fetch, if any. Kept so re-entry can't double-scan and so
    /// the fetch can be cancelled when the user leaves the screen (D-01).
    private var scanTask: Task<Void, Never>?

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
        load()
    }

    /// Kicks off the screenshot fetch, flipping `isLoading` so the skeleton
    /// shows. No-op when a fetch is already in flight (D-01 re-entry guard).
    func load() {
        startScan()
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under
    /// the pull-to-refresh spinner. No-op while a scan is already running.
    func refresh() async {
        guard scanTask == nil else { return }
        errorMessage = nil
        scanTask = Task {
            screenshots = await photoService.fetchScreenshots()
            hasLoadedScreenshots = true
            scanTask = nil
        }
    }

    /// Starts (or no-ops if already running) the screenshot scan. The scan is
    /// tracked so `cancelScan()` can stop it when the user leaves the screen
    /// instead of it running detached (D-01).
    func startScan() {
        guard scanTask == nil else { return }
        isLoading = true
        errorMessage = nil
        scanTask = Task {
            screenshots = await photoService.fetchScreenshots()
            hasLoadedScreenshots = true
            isLoading = false
            scanTask = nil
        }
    }

    /// Cancels an in-flight fetch and clears the loading state. No-op when
    /// nothing is loading.
    func cancelScan() {
        guard scanTask != nil else { return }
        scanTask?.cancel()
        scanTask = nil
        if isLoading { isLoading = false }
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
