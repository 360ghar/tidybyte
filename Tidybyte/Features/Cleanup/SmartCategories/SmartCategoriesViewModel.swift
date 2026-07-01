import SwiftUI

@Observable
@MainActor
final class SmartCategoriesViewModel {
    var categorizedPhotos: [CategorizedPhoto] = [] {
        didSet { recomputeCategoryCounts() }
    }
    /// Per-category counts, recomputed only when `categorizedPhotos` changes so the
    /// chip row doesn't run an O(categories × photos) pass on every view update.
    private(set) var categoryCounts: [PhotoCategory: Int] = [:]
    var scanState: ScanState = .idle
    var selectedIds: Set<String> = []
    var activeCategory: PhotoCategory = .memes
    var errorMessage: String?
    var isDeleting = false

    var sensitivity: CategorySensitivity {
        AppPreferences.smartCategorySensitivity()
    }

    private let photoService = PhotoLibraryService()
    private let visionService = VisionAnalysisService()
    private let categorizationService: PhotoCategorizationService

    init() {
        categorizationService = PhotoCategorizationService(
            photoService: photoService,
            visionService: visionService
        )
    }

    var filteredPhotos: [CategorizedPhoto] {
        categorizedPhotos.filter { $0.categories.contains(activeCategory) }
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
        filteredPhotos.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.asset.fileSize }
    }

    /// Combined size of every photo in the active category (the whole list, not
    /// just the selection) — drives the count·size summary above the grid.
    var activeCategorySize: Int64 {
        filteredPhotos.reduce(0) { $0 + $1.asset.fileSize }
    }

    /// True when every photo currently visible (active category) is selected —
    /// drives the Select All / Deselect All toolbar toggle.
    var allVisibleSelected: Bool {
        !filteredPhotos.isEmpty && filteredPhotos.allSatisfy { selectedIds.contains($0.id) }
    }

    func scan() async {
        scanState = .scanning(0)
        categorizedPhotos = []
        selectedIds.removeAll()

        let assets = await photoService.fetchAllPhotos()
        let results = await categorizationService.categorize(
            assets: assets,
            sensitivity: sensitivity
        ) { [weak self] progress in
            Task { @MainActor in
                self?.scanState = .scanning(progress)
            }
        }

        if Task.isCancelled {
            scanState = .idle
            return
        }

        categorizedPhotos = results
        // Land on the first category that actually has results.
        if let first = nonEmptyCategories.first {
            activeCategory = first
        }
        scanState = .completed
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    func selectAll() {
        selectedIds = Set(filteredPhotos.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func synchronizeSelectionWithActiveCategory() {
        // Scope the selection to the visible category so the action-bar count and
        // the Delete action always match what the user can actually see.
        selectedIds.formIntersection(Set(filteredPhotos.map(\.id)))
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedIds))
            categorizedPhotos.removeAll { selectedIds.contains($0.id) }
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
            categorizedPhotos.removeAll { $0.id == assetId }
            selectedIds.remove(assetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
