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

    var sensitivity: BlurSensitivity {
        AppPreferences.blurSensitivity()
    }

    private let photoService = PhotoLibraryService()
    private let visionService = VisionAnalysisService()

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

            // Prefer a sharp, on-device, exactly-sized image so sharpness is
            // measured accurately; fall back to a fast thumbnail for assets whose
            // full resolution lives only in iCloud (so they're still analyzed).
            var uiImage = await photoService.loadAnalysisImage(for: photo.id, targetSize: CGSize(width: 512, height: 512))
            if uiImage == nil {
                uiImage = await photoService.loadThumbnail(for: photo.id, size: CGSize(width: 300, height: 300))
            }
            guard let cgImage = uiImage?.cgImage else {
                continue
            }

            let blurResult = await visionService.analyzeBlurriness(image: cgImage, assetId: photo.id, sensitivity: sensitivity)
            let exposureResult = await visionService.analyzeExposure(image: cgImage, assetId: photo.id)

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
                    categories: categories
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
