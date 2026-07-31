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
    var analyzedPhotos: [AnalyzedPhoto] = []
    var scanState: ScanState = .idle
    var selectedIds: Set<String> = []
    var activeTab: BlurryTab = .blurry
    var errorMessage: String?
    var isDeleting = false
    /// Number of screenshots excluded from analysis on the most recent scan
    /// (they're covered by the dedicated Screenshots tool) — surfaced in the
    /// results footer (D-04).
    private(set) var skippedScreenshotCount = 0

    /// The in-flight scan, if any. Kept so scans can be cancelled when the
    /// user leaves the screen and so re-entry can't start a second scan (D-01).
    private var scanTask: Task<Void, Never>?

    var sensitivity: BlurSensitivity {
        AppPreferences.blurSensitivity()
    }

    private let photoService = PhotoLibraryService()
    private let visionService = VisionAnalysisService()

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
        guard scanTask == nil else { return }
        scanTask = Task {
            await scan()
            scanTask = nil
        }
    }

    /// Cancels an in-flight scan and returns the tool to `.idle`. No-op when
    /// nothing is scanning.
    func cancelScan() {
        guard scanTask != nil else { return }
        scanTask?.cancel()
        scanTask = nil
        if case .scanning = scanState {
            scanState = .idle
        }
    }

    var filteredPhotos: [AnalyzedPhoto] {
        analyzedPhotos.filter { $0.categories.contains(activeTab) }
    }

    var blurryCount: Int { analyzedPhotos.filter { $0.categories.contains(.blurry) }.count }
    var darkCount: Int { analyzedPhotos.filter { $0.categories.contains(.tooDark) }.count }
    var overexposedCount: Int { analyzedPhotos.filter { $0.categories.contains(.overexposed) }.count }

    var selectedSize: Int64 {
        filteredPhotos.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.asset.fileSize }
    }

    func scan() async {
        scanState = .scanning(0)
        analyzedPhotos = []
        // D-02: stale selections from a previous scan must not persist across
        // rescans (mirrors SmartCategoriesViewModel.scan()).
        selectedIds.removeAll()
        skippedScreenshotCount = 0

        let allPhotos = await photoService.fetchAllPhotos()
        let total = allPhotos.count

        for (index, photo) in allPhotos.enumerated() {
            if Task.isCancelled {
                scanState = .idle
                return
            }
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
            var uiImage = await photoService.loadAnalysisImage(for: photo.id, targetSize: CGSize(width: 512, height: 512))
            let usedFallback = uiImage == nil
            if uiImage == nil {
                uiImage = await photoService.loadThumbnail(for: photo.id, size: CGSize(width: 300, height: 300))
            }
            guard let cgImage = uiImage?.cgImage else {
                continue
            }

            let blurResult = await visionService.analyzeBlurriness(image: cgImage, assetId: photo.id, sensitivity: sensitivity)
            let exposureResult = await visionService.analyzeExposure(image: cgImage, assetId: photo.id)

            if Task.isCancelled {
                scanState = .idle
                return
            }

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
                scanState = .scanning(Float(index + 1) / Float(max(total, 1)))
            }
        }

        scanState = .scanning(1.0)
        scanState = .completed
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    /// `allSatisfy` rather than count equality: `selectedIds` can briefly hold
    /// off-tab ids between a tab change and `synchronizeSelectionWithActiveTab()`.
    var allVisibleSelected: Bool {
        !filteredPhotos.isEmpty && filteredPhotos.allSatisfy { selectedIds.contains($0.id) }
    }

    func selectAll() {
        selectedIds = Set(filteredPhotos.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func synchronizeSelectionWithActiveTab() {
        selectedIds.formIntersection(Set(filteredPhotos.map(\.id)))
    }

    func deleteSelected() async {
        guard !selectedIds.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedIds))
            analyzedPhotos.removeAll { selectedIds.contains($0.id) }
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
            analyzedPhotos.removeAll { $0.id == assetId }
            selectedIds.remove(assetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
