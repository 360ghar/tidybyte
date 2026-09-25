import SwiftUI

enum BlurryTab: String, CaseIterable {
    case blurry = "Blurry"
    case tooDark = "Too Dark"
    case overexposed = "Overexposed"
}

struct AnalyzedPhoto: Identifiable, Sendable {
    let id: String
    let asset: AssetSummary
    let blurScore: Float
    let luminance: Float
    let categories: Set<BlurryTab>
    /// True when the analysis image came from the degraded fast-format
    /// thumbnail fallback (asset's full resolution lives only in iCloud) —
    /// such photos can read as blurrier than they really are (D-03).
    let isFallbackAnalysis: Bool
}

@Observable
@MainActor
final class BlurryPhotosViewModel {
    var analyzedPhotos: [AnalyzedPhoto] = [] {
        didSet {
            filterCache = nil
            if scanState == .completed { ScanResults.record(.blurry, count: analyzedPhotos.count) }
        }
    }
    var scanState: ScanState = .idle
    var activeTab: BlurryTab = .blurry
    var errorMessage: String?
    var isDeleting = false
    /// DUP-04/DUP-09 parity: how many items the last delete actually removed,
    /// so the view can gate the success haptic on a non-zero result (C12).
    private(set) var deletedCount = 0
    /// Number of screenshots excluded from analysis on the most recent scan
    /// (they're covered by the dedicated Screenshots tool) — surfaced in the
    /// results footer (D-04).
    private(set) var skippedScreenshotCount = 0

    /// C1/C2: owns the cancellable scan task + generation token.
    private let scanRunner = ScanRunner()

    var sensitivity: BlurSensitivity {
        AppPreferences.blurSensitivity()
    }

    private let photoService = PhotoLibraryService.shared
    private let visionService = VisionAnalysisService()

    /// One selection per photo, shared by all tabs. A photo that is both
    /// blurry and too dark shows the same check on both tabs, and the action
    /// bar, the confirm and the delete all count the same set. Switching tabs
    /// keeps every pick (C11).
    var selectedIds: Set<String> = []

    var totalSelectedCount: Int { selectedIds.count }

    /// Selected photos not shown on the active tab.
    var selectedOnOtherTabs: Int {
        selectedIds.subtracting(filteredPhotos.map(\.id)).count
    }

    /// Eligibility for quality analysis: screenshots are excluded — they're
    /// covered by the dedicated Screenshots tool. Live Photos ARE analyzed:
    /// their still frame can still be blurry/overexposed and no other tool
    /// covers them (D-04).
    nonisolated static func shouldAnalyze(_ asset: AssetSummary) -> Bool {
        !asset.isScreenshot
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

    /// Memoized filter + per-tab counts (C13 parity with
    /// `ScreenshotCleanerViewModel.sortedScreenshots`): the results view reads
    /// `filteredPhotos` in the toolbar, grid, alert, and preview sheet, so the
    /// computed filters re-ran ~9 full-array passes per render — including on
    /// every selection toggle, which changes no photo. Keyed by tab; the
    /// `analyzedPhotos` didSet invalidates on every mutation (scan appends,
    /// deletes). During a scan each progress tick still rebuilds once, same as
    /// before; after the scan, renders are free.
    private var filterCache: (tab: BlurryTab, filtered: [AnalyzedPhoto], counts: [BlurryTab: Int])?

    private func filteredAndCounts() -> (filtered: [AnalyzedPhoto], counts: [BlurryTab: Int]) {
        if let cache = filterCache, cache.tab == activeTab {
            return (cache.filtered, cache.counts)
        }
        var counts: [BlurryTab: Int] = [:]
        var filtered: [AnalyzedPhoto] = []
        for photo in analyzedPhotos {
            for category in photo.categories {
                counts[category, default: 0] += 1
            }
            if photo.categories.contains(activeTab) {
                filtered.append(photo)
            }
        }
        filterCache = (activeTab, filtered, counts)
        return (filtered, counts)
    }

    var filteredPhotos: [AnalyzedPhoto] {
        filteredAndCounts().filtered
    }

    var blurryCount: Int { filteredAndCounts().counts[.blurry] ?? 0 }
    var darkCount: Int { filteredAndCounts().counts[.tooDark] ?? 0 }
    var overexposedCount: Int { filteredAndCounts().counts[.overexposed] ?? 0 }

    var selectedSize: Int64 {
        analyzedPhotos.totalFileSize(selectedIds: selectedIds, idOf: \.id, sizeOf: { $0.asset.fileSize })
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
        scanState = .scanning(0)
        analyzedPhotos = []
        // D-02: stale selections from a previous scan must not persist across
        // rescans (all tabs — mirrors SmartCategoriesViewModel.scan()).
        selectedIds.removeAll()
        skippedScreenshotCount = 0
        deletedCount = 0
        pendingPrune = false

        let allPhotos = await photoService.fetchAllPhotos()
        let total = allPhotos.count
        // One batched PhotoKit resolve for the whole scan — the per-image
        // loaders below would otherwise do one identifier lookup per photo
        // (plus a second for every iCloud fallback).
        let phById = photoService.phAssetsById(allPhotos.map(\.id))

        for (index, photo) in allPhotos.enumerated() {
            // A cancelled scan leaves the state alone: `cancelScan()` already
            // moved the UI to `.idle`, and writing it here would stomp a scan
            // the user restarted while this one was unwinding (C1/C2).
            if Task.isCancelled { return }
            // Yield periodically to reduce memory pressure and allow UI updates
            if index % 20 == 0 {
                await Task.yield()
            }

            // D-04: screenshots are handled by the dedicated Screenshots tool;
            // Live Photos stay eligible (see `shouldAnalyze`).
            guard Self.shouldAnalyze(photo) else {
                skippedScreenshotCount += 1
                continue
            }

            // Prefer a sharp, on-device, exactly-sized image so sharpness is
            // measured accurately; fall back to a fast thumbnail for assets
            // whose full resolution lives only in iCloud (so they're still
            // analyzed). Fallback analysis is flagged so the UI can warn that
            // a low-res copy may read as softer than the original (D-03).
            // `phById` was resolved once up front — no per-photo fetch.
            // (Missing = deleted externally mid-scan; skip like a nil image.)
            var uiImage: UIImage?
            var usedFallback = true
            if let phAsset = phById[photo.id] {
                uiImage = await photoService.loadAnalysisImage(for: phAsset, targetSize: CGSize(width: 512, height: 512))
                usedFallback = uiImage == nil
                if uiImage == nil {
                    uiImage = await photoService.loadThumbnail(for: phAsset, size: CGSize(width: 300, height: 300))
                }
            }
            guard let cgImage = uiImage?.cgImage else {
                continue
            }

            let blurResult = await visionService.analyzeBlurriness(image: cgImage, assetId: photo.id, sensitivity: sensitivity)
            let exposureResult = await visionService.analyzeExposure(image: cgImage)

            if Task.isCancelled { return }

            var categories = Set<BlurryTab>()
            if blurResult.isBlurry {
                categories.insert(.blurry)
            }
            if exposureResult.isTooDark {
                categories.insert(.tooDark)
            }
            if exposureResult.isOverexposed {
                categories.insert(.overexposed)
            }

            if !categories.isEmpty {
                analyzedPhotos.append(AnalyzedPhoto(
                    id: photo.id,
                    asset: photo,
                    blurScore: blurResult.blurScore,
                    luminance: exposureResult.meanLuminance,
                    categories: categories,
                    isFallbackAnalysis: usedFallback
                ))
            }

            if index % 10 == 0 {
                // C2: dropped when the scan is no longer current.
                scanRunner.update(token) { self.scanState = .scanning(Float(index + 1) / Float(max(total, 1))) }
            }
        }

        // A cancelled or superseded run must never publish progress/results.
        guard !Task.isCancelled, scanRunner.isCurrent(token) else { return }

        scanState = .scanning(1.0)
        scanState = .completed
        // A library change that landed mid-scan: prune now that publishing
        // can't be overwritten by a later tick.
        if pendingPrune {
            pendingPrune = false
            await pruneDeleted()
        }
        ScanResults.record(.blurry, count: analyzedPhotos.count, epoch: scanEpoch)
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
        guard scanState == .completed, !analyzedPhotos.isEmpty, !isDeleting else { return }
        // Snapshot before the await: a new scan can replace `analyzedPhotos`
        // while we suspend, and applying the old membership set to the fresh
        // results would drop them.
        let scannedIds = analyzedPhotos.map(\.id)
        let present = await PhotoLibraryService.shared.existingIds(scannedIds)
        guard present.count < scannedIds.count else { return }
        guard scanState == .completed, !isDeleting else { return }
        let goneIds = Set(scannedIds.filter { !present.contains($0) })
        analyzedPhotos.removeAll { goneIds.contains($0.id) }
        selectedIds.subtract(goneIds)
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    /// `allSatisfy` rather than count equality: `selectedIds` also holds picks
    /// from other tabs.
    var allVisibleSelected: Bool {
        !filteredPhotos.isEmpty && filteredPhotos.allSatisfy { selectedIds.contains($0.id) }
    }

    /// Select All / Deselect All act on the visible tab only.
    func selectAll() {
        selectedIds.formUnion(filteredPhotos.map(\.id))
    }

    func deselectAll() {
        selectedIds.subtract(filteredPhotos.map(\.id))
    }

    func deleteSelected() async {
        // C11: delete across ALL tabs' selections — a batch isn't limited to
        // the visible tab.
        let allSelected = selectedIds
        guard !allSelected.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        // Sizes captured before the await (the assets are gone afterwards).
        let sizeById = analyzedPhotos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: allSelected,
            kind: .blurry,
            sizeById: sizeById,
            apply: { deletedIds in
                analyzedPhotos.removeAll { deletedIds.contains($0.id) }
                selectedIds.subtract(deletedIds)
            },
            recordDeleted: { self.deletedCount = $0 }
        )
        errorMessage = outcome.errorMessage
    }

    func delete(assetId: String) async -> Bool {
        guard !isDeleting else { return !analyzedPhotos.contains(where: { $0.id == assetId }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        let sizeById = analyzedPhotos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }
        let outcome = await CleanupDeletion.delete(
            requestedIds: [assetId],
            kind: .blurry,
            sizeById: sizeById,
            apply: { deletedIds in
                analyzedPhotos.removeAll { deletedIds.contains($0.id) }
                selectedIds.subtract(deletedIds)
            },
            recordDeleted: { self.deletedCount = $0 }
        )
        errorMessage = outcome.errorMessage
        return !analyzedPhotos.contains(where: { $0.id == assetId })
    }
}
