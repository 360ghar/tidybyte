import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import MacOSCleanerCore

private actor FixturePhotos: PhotoMutationService {
    enum Failure { case none, export, replacement, deletion, cancellation }
    let folder: URL
    let failure: Failure
    var calls: [String] = []
    init(folder: URL, failure: Failure) {
        self.folder = folder
        self.failure = failure
    }
    func previewURL(for item: ReviewItem) async throws -> URL { folder.appendingPathComponent(item.name) }
    func localURLs(for item: ReviewItem) async throws -> [URL] { [try await previewURL(for: item)] }
    func export(_ item: ReviewItem, to folder: URL) async throws -> [URL] {
        calls.append("export")
        let output = folder.appendingPathComponent(item.name)
        try Data("original".utf8).write(to: output)
        if failure == .export { throw CleanupError.message("Export verification failed") }
        return [output]
    }
    func replace(_ item: ReviewItem, with url: URL, kind: MediaKind) async throws -> String {
        calls.append("replace")
        if failure == .replacement { throw CleanupError.message("Import verification failed") }
        if failure == .cancellation { withUnsafeCurrentTask { $0?.cancel() } }
        return "verified-replacement"
    }
    func delete(_ item: ReviewItem) async throws {
        calls.append("delete")
        if failure == .deletion { throw CleanupError.message("Deletion denied") }
    }
}

private actor InventoryProgress {
    var updates = 0
    func record() { updates += 1 }
}

final class CleanupMediaSafetyTests: XCTestCase {
    private func fixture() throws -> URL {
        try TestFixtures.makeTemporaryDirectory(named: "CleanupMedia-" + UUID().uuidString)
    }
    private func photo() -> ReviewItem {
        var item = ReviewItem(id: "photo", source: .photos("fixture"), name: "image.jpg", kind: .image, bytes: 100)
        item.resources = [PhotoResource(name: "image.jpg", type: 1, uniformType: "public.jpeg")]
        item.resources[0].bytes = 60
        return item
    }
    private func jpeg(at url: URL, solid: Bool = false) throws {
        let width = 640
        let height = 480
        var state: UInt64 = 1
        let pixels: [UInt8] = (0..<(width * height * 4)).map { index in
            if index % 4 == 3 { return 255 }
            if solid { return 10 }
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return UInt8(truncatingIfNeeded: state >> 32)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let writer = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    func testPhotosMoveNeverDeletesAfterFailedExportVerification() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore.inMemory()
        let photos = FixturePhotos(folder: root, failure: .export)
        let executor = ReviewExecutor(store: store, access: FolderAccess(store: store), photos: photos, trash: FixtureTrash())
        let result = await executor.apply(
            ReviewDecision(item: photo(), choice: .move, destination: root),
            tool: .swipe, operationID: "export-failure")
        let calls = await photos.calls
        XCTAssertEqual(calls, ["export"])
        XCTAssertEqual(result.state, .interrupted)
        XCTAssertEqual(result.savings, 0)
        XCTAssertNotNil(result.outputURL)
    }

    func testPhotosReplacementMustVerifyBeforeDeletion() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore.inMemory()
        let photos = FixturePhotos(folder: root, failure: .replacement)
        let executor = ReviewExecutor(store: store, access: FolderAccess(store: store), photos: photos, trash: FixtureTrash())
        let result = await executor.keepPhotoResource(photo(), index: 0)
        let calls = await photos.calls
        XCTAssertEqual(calls, ["replace"])
        XCTAssertNotEqual(result.state, .complete)
        XCTAssertEqual(result.savings, 0)
    }

    func testPhotosDeleteFailureRetainsVerifiedReplacementInJournal() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore.inMemory()
        let photos = FixturePhotos(folder: root, failure: .deletion)
        let executor = ReviewExecutor(store: store, access: FolderAccess(store: store), photos: photos, trash: FixtureTrash())
        let result = await executor.keepPhotoResource(photo(), index: 0)
        let calls = await photos.calls
        XCTAssertEqual(calls, ["replace", "delete"])
        XCTAssertEqual(result.replacementPhotoID, "verified-replacement")
        XCTAssertEqual(result.state, .interrupted)
        XCTAssertEqual(result.savings, 0)
        let journal = try await store.cleanupActivity()
        XCTAssertEqual(journal.first?.replacementPhotoID, "verified-replacement")
    }

    func testCancellationAfterPhotosImportLeavesOriginal() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore.inMemory()
        let photos = FixturePhotos(folder: root, failure: .cancellation)
        let executor = ReviewExecutor(store: store, access: FolderAccess(store: store), photos: photos, trash: FixtureTrash())
        let input = photo()
        let task = Task { await executor.keepPhotoResource(input, index: 0) }
        let result = await task.value
        let calls = await photos.calls
        XCTAssertEqual(calls, ["replace"])
        XCTAssertEqual(result.state, .interrupted)
    }

    func testCancelledPhotoOperationsDoNotImportOrDelete() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore.inMemory()
        let photos = FixturePhotos(folder: root, failure: .none)
        let executor = ReviewExecutor(store: store, access: FolderAccess(store: store), photos: photos, trash: FixtureTrash())
        let item = photo()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = await executor.keepPhotoResource(item, index: 0)
            return await executor.apply(
                ReviewDecision(item: item, choice: .trash), tool: .swipe, operationID: "cancelled")
        }
        let result = await task.value
        XCTAssertNotEqual(result.state, .complete)
        let calls = await photos.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testQualityTabsIncludeEveryApplicableIssue() {
        var item = photo()
        item.facts.luminance = 0.05
        item.facts.sharpness = 0
        XCTAssertEqual(
            Set(MediaAnalysisService.qualityIssues(item, sensitivity: 1)), ["Too dark", "Out of focus"])
        item.isDownloaded = false
        XCTAssertTrue(MediaAnalysisService.qualityIssues(item, sensitivity: 1).isEmpty)
    }

    func testCompressionVerifiesDimensionsAndAvoidsNameCollision() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("noise.jpg")
        try jpeg(at: source)
        let collision = root.appendingPathComponent("noise-compressed.jpg")
        try Data("existing output".utf8).write(to: collision)
        let item = try XCTUnwrap(ReviewInventory.record(source, root: root))
        let output = try await MediaCompressionService().compress(
            item, source: source, destination: root,
            settings: CleanupSettings()
        ) { _ in }
        XCTAssertNotEqual(output, collision)
        XCTAssertEqual(try String(contentsOf: collision, encoding: .utf8), "existing output")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertLessThan(try ReviewSafety.identity(at: output).sizeBytes ?? .max, item.bytes)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertEqual(image.width, 640)
        XCTAssertEqual(image.height, 480)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".cleaner-") })
    }

    func testLocalQualityScoresSeparateFlatDarkAndDetailedImages() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dark = root.appendingPathComponent("dark.jpg")
        let detailed = root.appendingPathComponent("detail.jpg")
        try jpeg(at: dark, solid: true)
        try jpeg(at: detailed)
        let dim = try ImageQualityAnalysis.measureImage(dark, original: MediaFacts(), sensitivity: 1)
        let sharp = try ImageQualityAnalysis.measureImage(detailed, original: MediaFacts(), sensitivity: 1)
        XCTAssertLessThan(dim.facts.luminance ?? 1, 0.12)
        XCTAssertLessThan(dim.facts.sharpness ?? 1, sharp.facts.sharpness ?? 0)
    }

    func testExactAndVisualGroupsHaveDistinctIdentifiers() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.jpg")
        let second = root.appendingPathComponent("second.jpg")
        try jpeg(at: first)
        try FileManager.default.copyItem(at: first, to: second)
        let items = try [first, second].map { try XCTUnwrap(ReviewInventory.record($0, root: root)) }
        let store = try SQLiteStore.inMemory()
        let result = try await MediaAnalysisService(photos: PhotoLibraryService(), store: store)
            .analyze(items, scopeID: "fixture", settings: CleanupSettings()) { _ in }
        let groups = result.groups.filter { $0.tool == .duplicates }
        XCTAssertGreaterThanOrEqual(groups.count, 1)
        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)
        XCTAssertTrue(groups.contains { $0.explanation == "Exact content match" })
        XCTAssertEqual(Set(groups.flatMap(\.memberIDs)), Set(items.map(\.id)))
    }

    func testHardLinksHaveSeparateReviewIDs() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        try Data("same inode".utf8).write(to: first)
        try FileManager.default.linkItem(at: first, to: second)
        let lhs = try XCTUnwrap(ReviewInventory.record(first, root: root))
        let rhs = try XCTUnwrap(ReviewInventory.record(second, root: root))
        XCTAssertEqual(lhs.identity?.inodeIdentifier, rhs.identity?.inodeIdentifier)
        XCTAssertNotEqual(lhs.id, rhs.id)
    }

    func testDocumentPackageSizeAndContentVersion() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Report.pages")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        let file = package.appendingPathComponent("data.txt")
        try Data("package".utf8).write(to: file)
        let before = try XCTUnwrap(ReviewInventory.record(package, root: root))
        XCTAssertTrue(before.isPackage)
        XCTAssertEqual(before.bytes, 7)
        try Data("changed package".utf8).write(to: file)
        XCTAssertThrowsError(try ReviewSafety.verify(before))
        let after = try XCTUnwrap(ReviewInventory.record(package, root: root))
        XCTAssertNotEqual(before.reviewKey, after.reviewKey)
    }

    func testTenThousandItemScanReportsProgress() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<10_000 { try Data("fixture".utf8).write(to: root.appendingPathComponent("\(index).txt")) }
        var scope = ReviewScope()
        scope.roots = [root]
        let progress = InventoryProgress()
        let inventory = ReviewInventory(access: FolderAccess(store: try SQLiteStore.inMemory()))
        let result = try await inventory.scan(scope) { _ in await progress.record() }
        XCTAssertEqual(result.count, 10_000)
        let count = await progress.updates
        XCTAssertEqual(count, 100)
    }
}
