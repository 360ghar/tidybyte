import SwiftUI

@Observable
@MainActor
final class SmartCategoriesViewModel {
    var categorizedPhotos: [CategorizedPhoto] = [] {
        didSet {
            indexRevision += 1
            cancelSearch()
            recomputeCategoryCounts()
            recomputeFiltered()
            if scanState == .completed { ScanResults.record(.smartCategories, count: categorizedPhotos.count) }
        }
    }
    /// Per-category counts, recomputed only when `categorizedPhotos` changes so the
    /// chip row doesn't run an O(categories × photos) pass on every view update.
    private(set) var categoryCounts: [PhotoCategory: Int] = [:]
    /// Memoized active-category filter + combined size (C13 parity with
    /// `ScreenshotCleanerViewModel.sortedScreenshots`): the results view reads
    /// `filteredPhotos` in the toolbar, grid, alert, and preview sheet, so a
    /// computed filter re-ran on every render. Refreshed by the `didSet`s above.
    private(set) var cachedFilteredPhotos: [CategorizedPhoto] = []
    private(set) var cachedActiveCategorySize: Int64 = 0
    var scanState: ScanState = .idle
    var activeCategory: PhotoCategory = .memes {
        didSet { recomputeFiltered() }
    }
    var errorMessage: String?
    var searchText = "" {
        didSet {
            cancelSearch()
            appliedSearch = nil
            searchMessage = nil
            recomputeFiltered()
        }
    }
    private(set) var searchMessage: String?
    private(set) var isSearching = false
    private(set) var skippedAnalysisCount = 0
    private var appliedSearch: PhotoSearchQuery?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var indexRevision = 0
    private let searchOperation: @Sendable (String, Set<String>) async -> PhotoSearchResult

    var isSearchActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func cancelSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    @discardableResult
    func submitSearch() -> Task<Void, Never>? {
        cancelSearch()
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        appliedSearch = nil
        recomputeFiltered()
        isSearching = true
        let token = searchGeneration
        let epoch = ScanResults.epoch
        let vocabulary = Set(categorizedPhotos.flatMap { $0.contentLabels.keys })
        searchTask = Task {
            let result = await searchOperation(text, vocabulary)
            guard !Task.isCancelled, token == searchGeneration else { return }
            guard epoch == ScanResults.epoch else {
                isSearching = false
                searchMessage = "Your library changed. Scan again before searching."
                return
            }
            appliedSearch = result.query
            searchMessage = result.message
            isSearching = false
            recomputeFiltered()
        }
        return searchTask
    }
    var isDeleting = false
    /// DUP-04/DUP-09 parity: how many items the last delete actually removed,
    /// so the view can gate the success haptic on a non-zero result (C12).
    private(set) var deletedCount = 0
    /// Number of photos the most recent scan attempted to categorize (used to
    /// judge whether a heuristic bucket is disproportionately large — D-06).
    /// Updated live during the scan so the "N sorted" counter ticks (C9).
    private(set) var analyzedPhotoCount = 0

    /// C1/C2: owns the cancellable scan task + generation token.
    private let scanRunner = ScanRunner()

    /// One selection per photo, shared by all categories (a screenshot that
    /// is also a document shows the same check in both). The action bar, the
    /// confirm and the delete all count this one set (C11).
    var selectedIds: Set<String> = []

    var totalSelectedCount: Int { selectedIds.count }

    /// Selected photos not shown in the active category.
    var selectedInOtherCategories: Int {
        selectedIds.subtracting(filteredPhotos.map(\.id)).count
    }

    var sensitivity: CategorySensitivity {
        AppPreferences.smartCategorySensitivity()
    }

    private let photoService = PhotoLibraryService.shared
    private let visionService = VisionAnalysisService()
    private let categorizationService: PhotoCategorizationService

    init(search: (@Sendable (String, Set<String>) async -> PhotoSearchResult)? = nil) {
        let intelligence = LocalPhotoIntelligence()
        searchOperation = search ?? { text, vocabulary in await intelligence.search(text, vocabulary: vocabulary) }
        categorizationService = PhotoCategorizationService(
            photoService: photoService,
            visionService: visionService
        )
    }

    var filteredPhotos: [CategorizedPhoto] {
        cachedFilteredPhotos
    }

    /// Categories that actually have matches, in canonical order — drives the
    /// chip selector so empty buckets aren't shown.
    var nonEmptyCategories: [PhotoCategory] {
        PhotoCategory.allCases.filter { (categoryCounts[$0] ?? 0) > 0 }
    }

    func count(for category: PhotoCategory) -> Int {
        categoryCounts[category] ?? 0
    }

    private func recomputeCategoryCounts() {
        var counts: [PhotoCategory: Int] = [:]
        for photo in categorizedPhotos {
            for category in photo.categories {
                counts[category, default: 0] += 1
            }
        }
        categoryCounts = counts
    }

    var selectedSize: Int64 {
        categorizedPhotos.totalFileSize(selectedIds: selectedIds, idOf: \.id, sizeOf: { $0.asset.fileSize })
    }

    /// Combined size of every photo in the active category (the whole list, not
    /// just the selection) — drives the count·size summary above the grid.
    var activeCategorySize: Int64 {
        cachedActiveCategorySize
    }

    /// True when every photo currently visible (active category) is selected —
    /// drives the Select All / Deselect All toolbar toggle.
    var allVisibleSelected: Bool {
        !cachedFilteredPhotos.isEmpty && cachedFilteredPhotos.allSatisfy { selectedIds.contains($0.id) }
    }

    private func recomputeFiltered() {
        let filtered = categorizedPhotos.filter { photo in
            if isSearchActive {
                return photo.wasAnalyzed && appliedSearch?.matches(labels: photo.contentLabels) == true
            }
            return photo.categories.contains(activeCategory)
        }
        cachedFilteredPhotos = filtered
        cachedActiveCategorySize = filtered.reduce(0) { $0 + $1.asset.fileSize }
    }

    /// Starts the scan unless one is already in flight. The scan runs in a
    /// tracked task so `cancelScan()` can stop it (D-01).
    func startScan() {
        scanRunner.start { [weak self] token in
            await self?.scan(token: token)
        }
    }

    /// Cancels an in-flight scan and returns the tool to `.idle`. No-op when
    /// nothing is scanning.
    func cancelScan() {
        guard scanRunner.isRunning else { return }
        scanRunner.cancel()
        if case .scanning = scanState {
            scanState = .idle
        }
    }

    func scan(token: Int) async {
        // A run whose token is already stale (cancelled before this body got a
        // turn on the main actor) must not touch shared state: `cancelScan()`
        // already moved the UI to `.idle`.
        guard scanRunner.isCurrent(token) else { return }
        // Captured before any await: a library change during the scan bumps the
        // epoch, and this run's result must then be dropped rather than
        // published as a pre-change count.
        let scanEpoch = ScanResults.epoch
        searchText = ""
        scanState = .scanning(0)
        categorizedPhotos = []
        selectedIds.removeAll()
        deletedCount = 0
        analyzedPhotoCount = 0

        let assets = await photoService.fetchAllPhotos()
        // C9: counted live so the "N sorted" indicator ticks during the scan.
        let photoCount = assets.filter { $0.mediaType == .photo }.count
        scanRunner.update(token) { self.analyzedPhotoCount = photoCount }
        let results = await categorizationService.categorize(
            assets: assets,
            sensitivity: sensitivity
        ) { [weak self] progress in
            Task { @MainActor in
                // C2: dropped when the scan is no longer current.
                self?.scanRunner.update(token) { self?.scanState = .scanning(progress) }
            }
        }

        // A cancelled or superseded run must never publish results: the user may
        // have restarted the scan while this one was still unwinding, and
        // `cancelScan()` already moved the UI to `.idle` (C1/C2).
        guard !Task.isCancelled, scanRunner.isCurrent(token) else { return }

        guard scanEpoch == ScanResults.epoch else {
            scanState = .idle
            errorMessage = "Your library changed during analysis. Scan again for current results."
            return
        }
        skippedAnalysisCount = max(0, photoCount - results.filter(\.wasAnalyzed).count)
        categorizedPhotos = results
        // Land on the first category that actually has results.
        if let first = nonEmptyCategories.first {
            activeCategory = first
        }
        scanState = .completed
        ScanResults.record(.smartCategories, count: categorizedPhotos.count, epoch: scanEpoch)
    }

    /// D-06: the "Saved from Apps" bucket is recall-heavy by design (filename
    /// heuristics). When it dominates the library, explain that detection is
    /// heuristic so users don't mistake it for ground truth.
    var categoryExplanation: String? {
        guard activeCategory == .savedFromApps else { return nil }
        let savedCount = count(for: .savedFromApps)
        // "Large relative to the library": at least 20% of analyzed photos.
        if savedCount > 0, savedCount * 5 >= max(analyzedPhotoCount, 1) {
            return "Detected by file name heuristics — may include some camera photos"
        }
        return nil
    }

    /// Drops results deleted elsewhere (Swipe Review, the Photos app).
    /// An in-flight scan rejects changed epochs before publishing instead.
    func pruneDeleted() async {
        guard scanState == .completed, !categorizedPhotos.isEmpty, !isDeleting else { return }
        cancelSearch()
        let token = indexRevision
        let epoch = ScanResults.epoch
        let unchanged = await photoService.unchangedAssetIDs(categorizedPhotos.map(\.asset))
        guard !Task.isCancelled, scanState == .completed, !isDeleting,
              token == indexRevision, epoch == ScanResults.epoch else { return }
        retainUnchangedPhotos(unchanged)
    }

    func retainUnchangedPhotos(_ unchanged: Set<String>) {
        let remaining = categorizedPhotos.filter { unchanged.contains($0.id) }
        guard remaining.count != categorizedPhotos.count else { return }
        categorizedPhotos = remaining
        selectedIds.formIntersection(categorizedPhotos.map(\.id))
        searchMessage = "Removed changed or unavailable photos. Scan again to include new or edited photos."
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    /// Select All / Deselect All act on the visible category only.
    func selectAll() {
        selectedIds.formUnion(filteredPhotos.map(\.id))
    }

    func deselectAll() {
        selectedIds.subtract(filteredPhotos.map(\.id))
    }

    private func removeIds(_ ids: Set<String>) {
        categorizedPhotos.removeAll { ids.contains($0.id) }
        selectedIds.subtract(ids)
    }

    func deleteSelected() async {
        // C11: delete across ALL categories' selections.
        let allSelected = selectedIds
        guard !allSelected.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        // Sizes captured before the await (the assets are gone afterwards).
        let sizeById = categorizedPhotos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: allSelected,
            kind: .smartCategories,
            sizeById: sizeById,
            apply: { removeIds($0) },
            recordDeleted: { self.deletedCount = $0 }
        )
        errorMessage = outcome.errorMessage
    }

    func delete(assetId: String) async -> Bool {
        guard !isDeleting else { return !categorizedPhotos.contains(where: { $0.id == assetId }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        let sizeById = categorizedPhotos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: [assetId],
            kind: .smartCategories,
            sizeById: sizeById,
            apply: { removeIds($0) },
            recordDeleted: { self.deletedCount = $0 }
        )
        errorMessage = outcome.errorMessage
        return !categorizedPhotos.contains(where: { $0.id == assetId })
    }
}
