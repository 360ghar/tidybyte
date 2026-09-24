import SwiftUI

@Observable
@MainActor
final class SmartCategoriesViewModel {
    var categorizedPhotos: [CategorizedPhoto] = [] {
        didSet {
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

    init() {
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
        let filtered = categorizedPhotos.filter { $0.categories.contains(activeCategory) }
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
        scanState = .scanning(0)
        categorizedPhotos = []
        selectedIds.removeAll()
        deletedCount = 0
        analyzedPhotoCount = 0
        pendingPrune = false

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

        categorizedPhotos = results
        // Land on the first category that actually has results.
        if let first = nonEmptyCategories.first {
            activeCategory = first
        }
        scanState = .completed
        // A library change that landed mid-scan: prune now that publishing
        // can't be overwritten by a later tick.
        if pendingPrune {
            pendingPrune = false
            await pruneDeleted()
        }
        ScanResults.record(.smartCategories, count: categorizedPhotos.count)
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
    /// A library change that lands mid-scan can't prune yet (results are
    /// still landing), so it's remembered and applied when the scan
    /// completes instead of being lost.
    private var pendingPrune = false

    func pruneDeleted() async {
        if case .scanning = scanState {
            pendingPrune = true
            return
        }
        guard scanState == .completed, !categorizedPhotos.isEmpty, !isDeleting else { return }
        let present = await PhotoLibraryService.shared.existingIds(categorizedPhotos.map(\.id))
        guard present.count < categorizedPhotos.count else { return }
        categorizedPhotos.removeAll { !present.contains($0.id) }
        selectedIds.formIntersection(present)
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
