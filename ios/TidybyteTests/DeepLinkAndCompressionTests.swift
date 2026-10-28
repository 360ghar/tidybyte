import XCTest
@testable import Tidybyte

final class DeepLinkAndCompressionTests: XCTestCase {

    // MARK: - DeepLink parsing

    func testDeepLinkStorage() {
        XCTAssertEqual(DeepLink.from(url: URL(string: "tidybyte://storage")!), .storage)
    }

    func testDeepLinkSwipe() {
        XCTAssertEqual(DeepLink.from(url: URL(string: "tidybyte://swipe")!), .swipe)
    }

    func testDeepLinkCleanupHome() {
        XCTAssertEqual(DeepLink.from(url: URL(string: "tidybyte://cleanup")!), .cleanupHome)
    }

    func testDeepLinkCleanupTool() {
        XCTAssertEqual(
            DeepLink.from(url: URL(string: "tidybyte://cleanup/screenshots")!),
            .cleanupTool(.screenshots)
        )
        XCTAssertEqual(
            DeepLink.from(url: URL(string: "tidybyte://cleanup/largeFiles")!),
            .cleanupTool(.largeFiles)
        )
    }

    func testDeepLinkUnknownToolFallsBackToCleanupHome() {
        XCTAssertEqual(
            DeepLink.from(url: URL(string: "tidybyte://cleanup/bogusTool")!),
            .cleanupHome
        )
    }

    func testDeepLinkRejectsForeignScheme() {
        XCTAssertNil(DeepLink.from(url: URL(string: "https://storage")!))
        XCTAssertNil(DeepLink.from(url: URL(string: "tidybyte://unknownhost")!))
    }

    // MARK: - CompressionRecord media type

    func testCompressionRecordDefaultsToVideo() {
        let record = CompressionRecord(
            assetLocalIdentifier: "a",
            originalSizeBytes: 100,
            compressedSizeBytes: 50,
            exportPreset: "720p"
        )
        XCTAssertEqual(record.mediaType, "video")
    }

    func testCompressionRecordPhotoMediaType() {
        let record = CompressionRecord(
            assetLocalIdentifier: "a",
            originalSizeBytes: 100,
            compressedSizeBytes: 50,
            exportPreset: "high",
            outcome: "completed",
            mediaType: "photo"
        )
        XCTAssertEqual(record.mediaType, "photo")
    }

    // MARK: - Photo compression presets

    func testPhotoCompressionPresetIdsAndQuality() {
        let ids = PhotoCompressionPreset.presets.map(\.id)
        XCTAssertEqual(ids, ["high", "balanced", "space"])
        // High quality keeps full resolution; the others downscale.
        XCTAssertNil(PhotoCompressionPreset.presets[0].maxDimension)
        XCTAssertNotNil(PhotoCompressionPreset.presets[1].maxDimension)
        XCTAssertTrue(PhotoCompressionPreset.presets.allSatisfy { $0.quality > 0 && $0.quality <= 1 })
    }
}
