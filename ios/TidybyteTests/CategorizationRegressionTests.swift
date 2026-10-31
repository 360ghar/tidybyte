import XCTest
@testable import Tidybyte

/// Regression tests for the Smart Categories taxonomy mapping (D-05) and the
/// Photo Quality (Blurry) eligibility rules (D-04). Covers the pure helpers
/// only — scan-loop behavior that depends on PhotoKit is not exercised here.
final class CategorizationRegressionTests: XCTestCase {

    // MARK: - bucket(forIdentifier:) normalization (D-05)

    func testExactMatch() {
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "food"), .food)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "whiteboard"), .documents)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "sunset"), .nature)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "dog"), .pets)
    }

    func testCaseDifferences() {
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "Food"), .food)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "WHITEBOARD"), .documents)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "Mountain"), .nature)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "Dog"), .pets)
    }

    func testSpaceVsUnderscore() {
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "baked_goods"), .food)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "baked goods"), .food)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "  Baked Goods  "), .food)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "sea"), .nature)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: " ocean "), .nature)
    }

    func testUnknownIdentifierReturnsNil() {
        XCTAssertNil(PhotoCategorizationService.bucket(forIdentifier: "quantum_computing"))
        XCTAssertNil(PhotoCategorizationService.bucket(forIdentifier: ""))
        XCTAssertNil(PhotoCategorizationService.bucket(forIdentifier: "   "))
        XCTAssertNil(PhotoCategorizationService.bucket(forIdentifier: "MixedCase"))
    }

    // MARK: - Priority order (D-05)

    /// Text-heavy content lands in `.memes` only for screenshots; every other
    /// text-heavy capture is a document/receipt/whiteboard.
    func testTextHeavyPrecedenceDocumentsBeforeMemes() {
        XCTAssertEqual(PhotoCategorizationService.textHeavyBucket(isScreenshot: false), .documents)
        XCTAssertEqual(PhotoCategorizationService.textHeavyBucket(isScreenshot: true), .memes)
    }

    /// Label-driven document identifiers must resolve to `.documents` and
    /// never collapse into the memes bucket.
    func testDocumentIdentifiersMapToDocuments() {
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "document"), .documents)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "receipt"), .documents)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "whiteboard"), .documents)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "menu"), .documents)
        XCTAssertEqual(PhotoCategorizationService.bucket(forIdentifier: "newspaper"), .documents)
    }

    // MARK: - Blurry eligibility (D-04)

    func testShouldAnalyzeExcludesScreenshots() {
        XCTAssertFalse(BlurryPhotosViewModel.shouldAnalyze(makeAsset(isScreenshot: true)))
    }

    func testShouldAnalyzeIncludesRegularAndLivePhotos() {
        XCTAssertTrue(BlurryPhotosViewModel.shouldAnalyze(makeAsset(isScreenshot: false)))
        XCTAssertTrue(BlurryPhotosViewModel.shouldAnalyze(makeAsset(isScreenshot: false, isLivePhoto: true)))
    }

    // MARK: - Helpers

    private func makeAsset(isScreenshot: Bool, isLivePhoto: Bool = false) -> AssetSummary {
        AssetSummary(
            id: UUID().uuidString,
            mediaType: .photo,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: 4000,
            pixelHeight: 3000,
            duration: 0,
            fileSize: 1_000_000,
            filename: "photo.jpg",
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: isLivePhoto,
            isScreenshot: isScreenshot,
            isLocallyAvailable: true
        )
    }
}
