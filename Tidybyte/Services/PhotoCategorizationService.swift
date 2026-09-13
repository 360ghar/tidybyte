import Photos
import UIKit

/// User-facing content buckets surfaced by the Smart Categories tool. A photo
/// can belong to several at once (e.g. a screenshot of a recipe → memes + food).
/// UI presentation (title/icon/color) is added as an extension in the view layer
/// so this service-layer enum stays free of SwiftUI.
enum PhotoCategory: String, CaseIterable, Sendable {
    case memes
    case documents
    case food
    case pets
    case nature
    case selfies
    case savedFromApps
    case other
}

/// A photo together with the set of categories it matched. Mirrors
/// `AnalyzedPhoto`/`DuplicateGroup` as the Sendable result type the categorizer
/// hands back to the view model.
struct CategorizedPhoto: Identifiable, Sendable {
    let id: String
    let asset: AssetSummary
    let categories: Set<PhotoCategory>
}

/// Coordinates the Smart Categories scan: fetches thumbnails, runs Vision
/// content classification via `VisionAnalysisService`, and maps the raw signals
/// into `PhotoCategory` buckets. Mirrors `DuplicateDetectionService`'s
/// actor-coordinator shape (injected services, progress closure, periodic
/// yielding, cooperative cancellation).
actor PhotoCategorizationService {
    private let photoService: PhotoLibraryService
    private let visionService: VisionAnalysisService

    init(photoService: PhotoLibraryService, visionService: VisionAnalysisService) {
        self.photoService = photoService
        self.visionService = visionService
    }

    func categorize(
        assets: [AssetSummary],
        sensitivity: CategorySensitivity,
        progress: @Sendable (Float) -> Void
    ) async -> [CategorizedPhoto] {
        let photos = assets.filter { $0.mediaType == .photo }
        let total = photos.count
        var results: [CategorizedPhoto] = []
        // One batched PhotoKit resolve for the whole scan — the per-id loader
        // below would otherwise do one identifier lookup per image.
        let phById = photoService.phAssetsById(photos.map(\.id))

        for (index, asset) in photos.enumerated() {
            if Task.isCancelled { return results }
            if index % 20 == 0 {
                await Task.yield()
            }

            var categories = Set<PhotoCategory>()
            // Origin-based bucket needs no image load.
            if asset.assetOrigin == .savedFromApp {
                categories.insert(.savedFromApps)
            }

            if let phAsset = phById[asset.id],
               let uiImage = await photoService.loadThumbnail(for: phAsset, size: CGSize(width: 300, height: 300)),
               let cgImage = uiImage.cgImage {
                let result = await visionService.classifyImageContent(
                    image: cgImage,
                    sensitivity: sensitivity
                )
                let matched = buckets(from: result, asset: asset, sensitivity: sensitivity)
                categories.formUnion(matched)
            }

            if !categories.isEmpty {
                results.append(CategorizedPhoto(
                    id: asset.id,
                    asset: asset,
                    categories: categories
                ))
            }

            if index % 10 == 0 {
                progress(Float(index + 1) / Float(max(total, 1)))
            }
        }

        return results
    }

    // MARK: - Mapping

    private func buckets(
        from result: ContentClassificationResult,
        asset: AssetSummary,
        sensitivity: CategorySensitivity
    ) -> Set<PhotoCategory> {
        var set = Set<PhotoCategory>()

        for (label, confidence) in result.labels where confidence > 0 {
            // D-05: identifiers are normalized on both sides (lowercased,
            // trimmed, spaces/hyphens→underscores) so Vision taxonomy variants
            // such as "Baked Goods" / "baked-goods" / "baked_goods" all resolve.
            if let bucket = Self.bucket(forIdentifier: label) {
                set.insert(bucket)
            }
        }

        // Text-heavy photos: a screenshot is most likely a meme/social capture,
        // anything else is a document/receipt/whiteboard.
        if result.textCoverage >= sensitivity.textCoverageThreshold {
            set.insert(Self.textHeavyBucket(isScreenshot: asset.isScreenshot))
        }

        // A face filling a large share of the frame reads as a selfie/portrait.
        if result.faceCoverage >= 0.10 {
            set.insert(.selfies)
        }

        return set
    }

    /// Maps Vision's scene/object taxonomy identifiers onto coarse user-facing
    /// buckets. Kept data-driven so it can be tuned without touching the scan
    /// loop. Keys are stored normalized (lowercased, underscores).
    private static let taxonomyToBucket: [String: PhotoCategory] = [
        // Food & drink
        "food": .food, "fruit": .food, "vegetable": .food, "meal": .food,
        "drink": .food, "beverage": .food, "dessert": .food, "baked_goods": .food,
        "dish": .food, "snack": .food, "produce": .food, "cuisine": .food,
        // Pets & animals
        "dog": .pets, "cat": .pets, "pet": .pets, "animal": .pets,
        "puppy": .pets, "kitten": .pets, "bird": .pets, "rabbit": .pets,
        // Nature & landscapes
        "plant": .nature, "flower": .nature, "tree": .nature, "foliage": .nature,
        "mountain": .nature, "hill": .nature, "beach": .nature, "coast": .nature,
        "sky": .nature, "cloud": .nature, "sunset": .nature, "sunrise": .nature,
        "landscape": .nature, "field": .nature, "forest": .nature, "lake": .nature,
        "river": .nature, "ocean": .nature, "sea": .nature, "waterfall": .nature,
        "snow": .nature, "garden": .nature, "park": .nature,
        // Documents
        "document": .documents, "receipt": .documents, "paper": .documents,
        "letter": .documents, "menu": .documents, "whiteboard": .documents,
        "book": .documents, "newspaper": .documents
    ]

    // MARK: - Normalization (D-05)

    /// Normalizes a taxonomy identifier for bucket lookup: lowercased, trimmed,
    /// and whitespace/hyphens collapsed to underscores. Vision emits identifier
    /// variants ("Baked Goods", "baked goods", "baked-goods", "baked_goods")
    /// that must all resolve to the same bucket (C4: hyphen variants previously
    /// fell through to nil despite the doc comment claiming otherwise).
    static func normalizeTaxonomyLabel(_ label: String) -> String {
        label.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    /// Pure, unit-testable lookup of a single taxonomy identifier. Applies
    /// `normalizeTaxonomyLabel` to the identifier so matching is robust to case
    /// and space-vs-underscore differences; returns `nil` for unknown labels.
    static func bucket(forIdentifier identifier: String) -> PhotoCategory? {
        taxonomyToBucket[normalizeTaxonomyLabel(identifier)]
    }

    /// Where a text-heavy photo lands: screenshots are meme/social captures,
    /// everything else is a document/receipt/whiteboard. Kept pure and
    /// testable so the intended precedence (documents before memes for
    /// non-screenshots) is pinned down.
    static func textHeavyBucket(isScreenshot: Bool) -> PhotoCategory {
        isScreenshot ? .memes : .documents
    }
}
