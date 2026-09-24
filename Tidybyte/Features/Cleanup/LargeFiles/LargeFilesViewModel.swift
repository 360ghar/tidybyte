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
    var assets: [AssetSummary] = [] {
        didSet { invalidateFilterCache() }
    }
    var isLoading = true
    private(set) var hasLoadedAssets = false
    var selectedIds: Set<String> = [] {
        didSet { refreshTotals() }
    }
    var mediaFilter: LargeFileFilter = .all {
        didSet { invalidateFilterCache() }
    }
    var sortOrder: LargeFileSortOrder = .largest {
        didSet { invalidateFilterCache() }
    }
    var errorMessage: String?
    var isDeleting = false

    // Share/export state
    var isPreparingShare = false
    var shareProgress: (completed: Int, total: Int) = (0, 0)
    var sharePayload: SharePayload?
    /// Temp folder backing the current share payload (or the just-finished
    /// export), tracked independently of `urls` so cleanup can always find it
    /// (LF-09).
    private(set) var shareExportFolder: URL?
    private var shareTask: Task<Void, Never>?

    /// Live view of the persisted preference (LF-06): never diverges from what
    /// Settings wrote, and any write goes straight to `AppPreferences`.
    var thresholdMB: Double {
        get { AppPreferences.largeFileThresholdMB() }
        set { AppPreferences.saveLargeFileThresholdMB(newValue) }
    }

    private let photoService = PhotoLibraryService.shared

    var thresholdBytes: Int64 {
        // Delegate to the shared helper so this stays in lockstep with any other
        // call site (e.g. the Storage dashboard's "Large Files" reclaim win).
        AppPreferences.largeFileThresholdBytes()
    }

    /// "Min size" label for the threshold slider. Uses the SAME byte formatter
    /// as the list rows (LF-05), so the stated minimum can never disagree with
    /// how a threshold-sized file renders in the list (a decimal "10 MB" label
    /// next to a binary "9.5 MB" row was the pre-fix inconsistency).
    static func minSizeLabel(thresholdMB: Double) -> String {
        "Min size: \(Int64(thresholdMB * 1_000_000).formattedFileSize)"
    }

    // MARK: - Filtering cache (LF-07)

    private var cachedFiltered: [AssetSummary]?
    private var cachedThreshold: Int64?
    private var cacheDirty = true

    /// Assets whose `fileSize` came back 0 (unknown) and are therefore excluded
    /// from the list; surfaced in the UI so big files don't vanish silently (LF-10).
    /// Derived directly from `assets` (not from the filtered-cache) so it can
    /// never go stale between cache invalidations.
    var zeroSizeCount: Int {
        assets.lazy.filter { $0.fileSize == 0 }.count
    }

    var filteredAssets: [AssetSummary] {
        let threshold = thresholdBytes
        if cacheDirty || cachedFiltered == nil || cachedThreshold != threshold {
            rebuildFiltered(threshold: threshold)
        }
        return cachedFiltered ?? []
    }

    private func rebuildFiltered(threshold: Int64) {
        let result = Self.computeFilteredAssets(
            from: assets,
            threshold: threshold,
            mediaFilter: mediaFilter,
            sortOrder: sortOrder
        )
        cachedFiltered = result
        cachedThreshold = threshold
        cacheDirty = false
        refreshTotals(from: result)
    }

    /// Memoized totals (C13): `totalSize`/`selectedSize`/`selectedVisibleCount`
    /// each reduced the filtered array on every render. Refreshed eagerly —
    /// from `rebuildFiltered()` and from the `selectedIds` didSet — so the
    /// cached values can never go stale between filter invalidations.
    private(set) var cachedTotalSize: Int64 = 0
    private(set) var cachedSelectedSize: Int64 = 0
    private(set) var cachedSelectedVisibleCount = 0

    private func refreshTotals() {
        refreshTotals(from: filteredAssets)
    }

    private func refreshTotals(from visible: [AssetSummary]) {
        cachedTotalSize = visible.reduce(0) { $0 + $1.fileSize }
        cachedSelectedSize = visible.totalFileSize(selectedIds: selectedIds)
        cachedSelectedVisibleCount = visible.reduce(0) { $0 + (selectedIds.contains($1.id) ? 1 : 0) }
    }

    private func invalidateFilterCache() {
        cacheDirty = true
        // Eager rebuild: assets/filter/sort mutations are infrequent (load,
        // delete, control changes), and this keeps the cached totals exact on
        // the very next render instead of one pass behind.
        refreshTotals()
    }

    /// Pure filter+sort pipeline so the cached getter stays a thin wrapper and
    /// ordering semantics are easy to pin down in tests.
    static func computeFilteredAssets(
        from assets: [AssetSummary],
        threshold: Int64,
        mediaFilter: LargeFileFilter,
        sortOrder: LargeFileSortOrder
    ) -> [AssetSummary] {
        var result = assets.filter { $0.fileSize >= threshold }
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
        cachedTotalSize
    }

    var selectedSize: Int64 {
        cachedSelectedSize
    }

    var selectedVisibleCount: Int {
        cachedSelectedVisibleCount
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
        apply(allAssets)
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh
    /// spinner. Current `mediaFilter`/`sortOrder`/`thresholdMB` state is preserved.
    func refresh() async {
        errorMessage = nil
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        apply(allAssets)
    }

    /// Shared load/refresh pipeline (de-slop D3).
    private func apply(_ newAssets: [AssetSummary]) {
        assets = newAssets.sorted { $0.fileSize > $1.fileSize }
        // Drop picks for files that no longer exist AND for files the list
        // can never show (below the size threshold, including zero-size
        // unknowns): an undisplayable pick would hold the action bar open
        // with nothing visible to act on. Picks hidden only by the media
        // filter or sort order are kept.
        let threshold = thresholdBytes
        selectedIds.formIntersection(newAssets.lazy.filter { $0.fileSize >= threshold }.map(\.id))
        hasLoadedAssets = true
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    /// Select All / Deselect All act on the visible files. Picks hidden by
    /// the filter or the size slider are kept, so peeking at another filter
    /// never throws away a selection.
    func selectAll() {
        selectedIds.formUnion(filteredAssets.map(\.id))
    }

    func deselectAll() {
        selectedIds.subtract(filteredAssets.map(\.id))
    }

    func deleteSelected() async {
        let visibleSelectedIds = Set(filteredAssets.map(\.id)).intersection(selectedIds)
        guard !visibleSelectedIds.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        // Freed bytes must be attributed from the pre-delete metadata — these
        // are the largest files in the library, so under-reporting here would
        // visibly understate the savings screen.
        let sizeById = assets.reduce(into: [String: Int64]()) { $0[$1.id] = $1.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: visibleSelectedIds,
            kind: .largeFiles,
            sizeById: sizeById,
            apply: { deletedIds in
                assets.removeAll { deletedIds.contains($0.id) }
                selectedIds.subtract(deletedIds)
            }
        )
        errorMessage = outcome.errorMessage
    }

    /// Deletes a single asset (used by the per-row trash button and the
    /// in-preview Delete action). Leaves selection mode untouched.
    func deleteAsset(id: String) async -> Bool {
        guard !isDeleting else { return !assets.contains(where: { $0.id == id }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        let sizeById = assets.reduce(into: [String: Int64]()) { $0[$1.id] = $1.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: [id],
            kind: .largeFiles,
            sizeById: sizeById,
            apply: {
                // Reconcile exactly what was deleted before surfacing the error.
                guard $0.contains(id) else { return }
                assets.removeAll { $0.id == id }
                selectedIds.remove(id)
            }
        )
        errorMessage = outcome.errorMessage
        return !assets.contains(where: { $0.id == id })
    }

    // MARK: - Share / Export

    /// Exports the visible selected assets to temp files and, when ready,
    /// publishes a `SharePayload` that the view presents in a share sheet.
    func startShare() {
        let ids = visibleSelectedIds
        guard !ids.isEmpty, !isPreparingShare else { return }
        isPreparingShare = true
        shareProgress = (0, ids.count)
        // D10 (LF-09 residual): sweep leftovers from previous sessions FIRST —
        // e.g. an export that finished after the user navigated back, whose
        // payload was set on a VM whose sheet never appeared. Serialized with
        // the new export by `isPreparingShare`, so nothing live is removed.
        Self.removeOrphanedShareExportFolders()
        // Strong capture (LF-09): the VM stays alive for the whole export so the
        // cleanup below always runs, even if the owning view is torn down while
        // the export is in flight.
        shareTask = Task {
            let urls = await self.photoService.exportAssetsForSharing(identifiers: ids) { [weak self] completed, total in
                self?.shareProgress = (completed, total)
            }
            let folder = urls.first?.deletingLastPathComponent()
            self.shareExportFolder = folder
            if urls.isEmpty {
                // Every resource failed to write. The temp folder's name is only
                // known inside the service, so sweep the app's export folders
                // (this VM is the only ShareExport-* user and exports are
                // serialized by `isPreparingShare`).
                Self.removeOrphanedShareExportFolders()
                self.shareExportFolder = nil
                self.errorMessage = "Couldn't prepare the selected items to share."
            } else if !Task.isCancelled {
                // Folder stays on disk until the share sheet is dismissed.
                self.sharePayload = SharePayload(urls: urls)
            } else {
                if let folder { Self.removeExportFolder(at: folder) }
                self.shareExportFolder = nil
            }
            self.isPreparingShare = false
        }
    }

    func cancelShare() {
        shareTask?.cancel()
        shareTask = nil
        isPreparingShare = false
    }

    /// Removes the temp export folder once the share sheet is dismissed.
    func cleanupShareExport() {
        if let folder = shareExportFolder {
            Self.removeExportFolder(at: folder)
        }
        shareExportFolder = nil
        sharePayload = nil
    }

    /// Idempotent: removing a folder that no longer exists is a no-op (LF-09).
    static func removeExportFolder(at folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Removes leftover `ShareExport-*` temp folders (used on the all-fail path
    /// where the exact folder name is unknowable from the VM).
    static func removeOrphanedShareExportFolders(in directory: URL = FileManager.default.temporaryDirectory) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where url.lastPathComponent.hasPrefix("ShareExport-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
