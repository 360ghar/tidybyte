import SwiftUI

enum ScreenshotSortOrder: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case largest = "Largest"
}

@Observable
@MainActor
final class ScreenshotCleanerViewModel {
    var screenshots: [AssetSummary] = [] {
        didSet { recomputeSorted() }
    }
    var isLoading = true
    private(set) var hasLoadedScreenshots = false
    var selectedIds: Set<String> = [] {
        didSet { recomputeSelectedSize() }
    }
    var sortOrder: ScreenshotSortOrder = .newest {
        didSet { recomputeSorted() }
    }
    var errorMessage: String?
    var isDeleting = false
    /// DUP-04/DUP-09 parity: how many items the last delete actually removed,
    /// so the view can gate the success haptic on a non-zero result (C12).
    private(set) var deletedCount = 0

    private let photoService = PhotoLibraryService.shared
    /// C1/C2: owns the cancellable scan task + generation token.
    private let scanRunner = ScanRunner()

    /// Cached sort (C13): `sortedScreenshots` used to be a computed property
    /// that re-sorted thousands of items on every access — and `body` touched
    /// it repeatedly, so every selection toggle re-sorted on the main thread.
    private(set) var sortedScreenshots: [AssetSummary] = []

    private func recomputeSorted() {
        switch sortOrder {
        case .newest:
            sortedScreenshots = screenshots.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .oldest:
            sortedScreenshots = screenshots.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .largest:
            sortedScreenshots = screenshots.sorted { $0.fileSize > $1.fileSize }
        }
        cachedTotalSize = screenshots.reduce(0) { $0 + $1.fileSize }
        recomputeSelectedSize()
    }

    /// Memoized totals (C13): `totalSize`/`selectedSize` reduced the whole
    /// array on every render. Totals refresh in `recomputeSorted()`; the
    /// selection-dependent one additionally refreshes on every `selectedIds`
    /// mutation via its `didSet`.
    private(set) var cachedTotalSize: Int64 = 0
    private(set) var cachedSelectedSize: Int64 = 0

    private func recomputeSelectedSize() {
        cachedSelectedSize = screenshots.totalFileSize(selectedIds: selectedIds)
    }

    var totalSize: Int64 {
        cachedTotalSize
    }

    var selectedSize: Int64 {
        cachedSelectedSize
    }

    /// Loads on first appearance. No-op when already loaded or loading (D-01).
    func loadIfNeeded() async {
        guard !hasLoadedScreenshots else { return }
        startScan()
    }

    /// Kicks off the screenshot fetch, flipping `isLoading` so the skeleton
    /// shows. No-op when a fetch is already in flight (D-01 re-entry guard).
    func startScan() {
        scanRunner.start { [weak self] _ in
            await self?.fetchScreenshots(showsLoading: true)
        }
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under
    /// the pull-to-refresh spinner. Serialized behind an in-flight fetch by the
    /// runner; runs even after a completed load (unlike `startScan`).
    func refresh() async {
        // Same serialized cancellable runner as `startScan` (own token, covered
        // by `cancelScan`), awaited so the caller suspends until results land.
        await scanRunner.run { [weak self] _ in
            await self?.fetchScreenshots(showsLoading: false)
        }
    }

    private func fetchScreenshots(showsLoading: Bool) async {
        if showsLoading { isLoading = true }
        errorMessage = nil
        let fetched = await photoService.fetchScreenshots()
        // C15: a cancelled fetch must not publish results or clear state —
        // previously Cancel was cosmetic for this tool.
        guard !Task.isCancelled else { return }
        screenshots = fetched
        selectedIds.formIntersection(Set(fetched.map(\.id)))
        hasLoadedScreenshots = true
        if showsLoading { isLoading = false }
    }

    /// Cancels an in-flight fetch and clears the loading state. No-op when
    /// nothing is loading.
    func cancelScan() {
        guard scanRunner.isRunning else { return }
        scanRunner.cancel()
        isLoading = false
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

    /// Matches the other tools (`BlurryPhotosViewModel.allVisibleSelected`):
    /// the toolbar's Select All reflects the sorted rows it actually selects.
    var allVisibleSelected: Bool {
        !sortedScreenshots.isEmpty && selectedIds.count == sortedScreenshots.count
    }

    private func removeIds(_ ids: Set<String>) {
        screenshots.removeAll { ids.contains($0.id) }
        selectedIds.subtract(ids)
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        // Sizes must be captured BEFORE the await: the deleted assets are gone
        // from the library afterwards, so this is the only place the freed
        // bytes can be attributed honestly.
        let sizeById = screenshots.reduce(into: [String: Int64]()) { $0[$1.id] = $1.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: selectedIds,
            kind: .screenshots,
            sizeById: sizeById,
            apply: { removeIds($0) },
            recordDeleted: { self.deletedCount = $0 }
        )
        errorMessage = outcome.errorMessage
    }

    func delete(assetId: String) async -> Bool {
        guard !isDeleting else { return !screenshots.contains(where: { $0.id == assetId }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        let sizeById = screenshots.reduce(into: [String: Int64]()) { $0[$1.id] = $1.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: [assetId],
            kind: .screenshots,
            sizeById: sizeById,
            apply: { removeIds($0) },
            recordDeleted: { self.deletedCount = $0 }
        )
        errorMessage = outcome.errorMessage
        return !screenshots.contains(where: { $0.id == assetId })
    }
}
