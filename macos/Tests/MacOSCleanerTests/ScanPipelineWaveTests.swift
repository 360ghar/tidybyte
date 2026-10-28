import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Review-wave tests (2026-08-01): system-clean section bridge consistency,
/// loud section-drift failure, and bounded-concurrency content extraction
/// preserving input order.
final class ScanPipelineWaveTests: XCTestCase {
    private func makeTemporaryDirectory(named prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Section bridge consistency (ScanMode <-> SystemCleanSection)

    func testEverySystemCleanScanModeHasASectionCounterpart() {
        for mode in ScanMode.allCases where mode.isSystemCleanSection {
            XCTAssertNotNil(mode.systemCleanSection, "\(mode.rawValue) must have a SystemCleanSection counterpart")
        }
    }

    func testEverySectionMapsBackToASystemCleanScanMode() {
        for section in MoCleanScanner.SystemCleanSection.allCases {
            let mode = ScanMode(rawValue: section.rawValue)
            XCTAssertNotNil(mode, "\(section.rawValue) must exist as a ScanMode")
            XCTAssertEqual(mode?.isSystemCleanSection, true, "\(section.rawValue) must be marked as a system-clean section")
        }
    }

    func testUnsupportedSectionErrorHasGuidance() {
        let error = ScanOrchestratorError.unsupportedSection(.deepSystem)
        XCTAssertFalse(error.localizedDescription.isEmpty)
        XCTAssertTrue(error.localizedDescription.contains("deepSystem"))
    }

    // MARK: - Content extraction order preservation with parallel workers

    func testContentExtractorPreservesOrderAndCount() async throws {
        let root = try makeTemporaryDirectory(named: "wave-extract")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURLs = (0..<8).map { root.appendingPathComponent("f\($0).txt") }
        for url in fileURLs {
            try Data("content-\(url.lastPathComponent)".utf8).write(to: url)
        }

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "wave")
        let recordsByPath = Dictionary(uniqueKeysWithValues: records.map { ($0.url.path, $0) })
        let ordered = fileURLs.compactMap { recordsByPath[$0.standardizedFileURL.path] }
        XCTAssertEqual(ordered.count, fileURLs.count, "Every fixture file must be crawled")

        let extractor = ContentExtractor()
        let summaries = await extractor.summarize(files: ordered, privacyMode: .snippetsAI)

        XCTAssertEqual(summaries.count, ordered.count, "Every text file must produce a summary")
        XCTAssertEqual(
            summaries.map(\.fileID),
            ordered.map(\.id),
            "Parallel extraction must preserve input order"
        )
        XCTAssertFalse(summaries.contains { ($0.textPreview ?? "").isEmpty }, "Text previews must be extracted")
    }

    func testContentExtractorLocalOnlyProducesNothing() async throws {
        let root = try makeTemporaryDirectory(named: "wave-extract-local")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("secret.txt")
        try Data("sensitive content".utf8).write(to: url)
        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "wave")
        let record = try XCTUnwrap(records.first { $0.url == url.standardizedFileURL })

        let extractor = ContentExtractor()
        let summaries = await extractor.summarize(files: [record], privacyMode: .localOnly)
        XCTAssertTrue(summaries.isEmpty, "localOnly must never extract or return content summaries")
    }
}
