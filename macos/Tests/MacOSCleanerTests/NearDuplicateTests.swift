import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacOSCleanerCore

/// Near-duplicate detection compares time-order neighbours only, so it must
/// still group a retake with its original, and never an unrelated image.
final class NearDuplicateTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = try TestFixtures.makeTemporaryDirectory(named: "NearDuplicate-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writePNG(_ name: String, size: Int, draw: (CGContext, CGFloat) -> Void) throws {
        let url = root.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context, CGFloat(size))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private static func sunset(_ context: CGContext, _ side: CGFloat) {
        context.setFillColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(red: 0.1, green: 0.1, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side * 0.4))
        context.setFillColor(red: 1, green: 0.95, blue: 0.6, alpha: 1)
        context.fillEllipse(in: CGRect(x: side * 0.35, y: side * 0.45, width: side * 0.3, height: side * 0.3))
    }

    /// The same scene, slightly smaller, with one small mark: a retake.
    private static func sunsetWithBird(_ context: CGContext, _ side: CGFloat) {
        sunset(context, side)
        context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: side * 0.2, y: side * 0.8, width: side * 0.03, height: side * 0.01))
    }

    private static func stripes(_ context: CGContext, _ side: CGFloat) {
        for index in 0..<12 {
            let shade = index.isMultiple(of: 2) ? 0.05 : 0.9
            context.setFillColor(red: shade, green: 0.8 - shade * 0.5, blue: shade, alpha: 1)
            context.fill(CGRect(x: CGFloat(index) * side / 12, y: 0, width: side / 12, height: side))
        }
    }

    func testRetakeIsGroupedAndAnUnrelatedImageIsNot() async throws {
        // Vision's feature-print request never returns on headless hosted CI
        // runners (every CI run froze on exactly this test, serial and
        // parallel, while the rest of the 492-test suite passed); it passes
        // in seconds in a normal GUI session.
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "Vision feature prints hang on headless CI runners")
        try writePNG("sunset.png", size: 512, draw: Self.sunset)
        try writePNG("sunset-small.png", size: 480, draw: Self.sunsetWithBird)
        try writePNG("stripes.png", size: 512, draw: Self.stripes)
        let files = await FileCrawler().crawl(rootURLs: [root], sessionID: "near").0

        let analysis = try await DuplicateDetector().analyze(files: files, sessionID: "near")

        let similar = analysis.findings.filter { $0.category == .duplicate && $0.summary.contains("visually similar") }
        XCTAssertEqual(similar.count, 1)
        let names = Set(files.filter { similar.first?.targetFileIDs.contains($0.id) == true }.map(\.fileName))
        XCTAssertEqual(names, ["sunset.png", "sunset-small.png"])
    }

    func testThresholdSeparatesUnrelatedImages() {
        // About 1 for unrelated images on the current feature print; 8 matched every pair.
        XCTAssertLessThan(DuplicateDetector.nearDuplicateDistanceThreshold, 0.9)
    }

    func testNearDuplicateWorkIsBounded() {
        XCTAssertLessThanOrEqual(DuplicateDetector.maxNearDuplicateImages, 20_000)
        XCTAssertLessThanOrEqual(DuplicateDetector.nearDuplicateWindow, 64)
    }
}
