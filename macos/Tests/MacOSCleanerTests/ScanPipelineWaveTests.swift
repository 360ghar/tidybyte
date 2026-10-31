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

    // MARK: - A stopped scan keeps what it found so far

    /// One-shot gate the scan task parks on inside its progress sink.
    private actor Gate {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            isOpen = true
            continuations.forEach { $0.resume() }
            continuations.removeAll()
        }
    }

    /// A cancelled scan must return a finalized partial outcome instead of
    /// throwing and discarding everything. The child task is parked in its
    /// progress sink when the group is cancelled, so it can never complete
    /// normally and the race is deterministic.
    func testCancelledScanReturnsPartialOutcomeInsteadOfThrowing() async throws {
        let root = try makeTemporaryDirectory(named: "wave-cancel")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let orchestrator = ScanOrchestrator(store: store, memory: memory)
        let gate = Gate()

        enum Attempt: Sendable {
            case returned(ScanOutcome, Plan)
            case threw(String)
        }

        let attempt = await withTaskGroup(of: Attempt.self) { group -> Attempt in
            group.addTask {
                do {
                    let (outcome, plan) = try await orchestrator.scan(
                        mode: .selectedFolders,
                        selectedFolders: [root],
                        providerSettings: ProviderSettings(),
                        includeAI: false,
                        progress: { _ in await gate.wait() })
                    return .returned(outcome, plan)
                } catch {
                    return .threw(String(describing: error))
                }
            }
            // The child is parked at step 1 (or still pending) — either way it
            // is registered, so cancelling here always lands before completion.
            group.cancelAll()
            await gate.open()
            return await group.next() ?? .threw("group ended without a result")
        }

        guard case .returned(let outcome, let plan) = attempt else {
            XCTFail("A stopped scan must return partial results, not throw: \(attempt)")
            return
        }
        XCTAssertTrue(outcome.wasCancelled, "A stopped scan must be marked as cancelled")
        XCTAssertEqual(outcome.session.status, .cancelled)
        XCTAssertNotNil(outcome.session.completedAt)
        XCTAssertNotNil(plan, "The partial scan still produces a plan for the review")
    }

    /// Signals when a crawl progress update carries items, then parks the
    /// caller until `resume()`. The final crawl snapshot runs on the crawl's
    /// own task, so parking there holds the scan before it can finalize.
    private actor CrawlProgressGate {
        private var seenItems = false
        private var seenWaiters: [CheckedContinuation<Void, Never>] = []
        private var release: CheckedContinuation<Void, Never>?

        func parkIfNeeded(itemsSeen: Int?) async {
            guard !seenItems, let itemsSeen, itemsSeen > 0 else { return }
            seenItems = true
            seenWaiters.forEach { $0.resume() }
            seenWaiters.removeAll()
            await withCheckedContinuation { release = $0 }
        }

        func waitUntilSeen() async {
            if seenItems { return }
            await withCheckedContinuation { seenWaiters.append($0) }
        }

        func resume() {
            release?.resume()
            release = nil
        }
    }

    /// Stop must return the crawled records without re-encoding them into
    /// SQLite: the bulk write is what made Stop look unresponsive on a large
    /// scan. The records still reach the review from the in-memory outcome.
    func testCancelledScanSkipsBulkPersistence() async throws {
        let root = try makeTemporaryDirectory(named: "wave-cancel-persist")
        defer { try? FileManager.default.removeItem(at: root) }
        let bulk = root.appendingPathComponent("bulk", isDirectory: true)
        try FileManager.default.createDirectory(at: bulk, withIntermediateDirectories: true)
        for index in 0..<100 {
            try Data("fixture-\(index)".utf8).write(to: bulk.appendingPathComponent("file-\(index).txt"))
        }

        let store = try SQLiteStore.inMemory()
        let orchestrator = ScanOrchestrator(store: store, memory: MemoryEngine(store: store))
        let gate = CrawlProgressGate()

        enum Attempt: Sendable {
            case returned(ScanOutcome, Plan)
            case threw(String)
        }

        let attempt = await withTaskGroup(of: Attempt.self) { group -> Attempt in
            group.addTask {
                do {
                    let (outcome, plan) = try await orchestrator.scan(
                        mode: .selectedFolders,
                        selectedFolders: [root],
                        providerSettings: ProviderSettings(),
                        includeAI: false,
                        progress: { update in await gate.parkIfNeeded(itemsSeen: update.filesSeen) })
                    return .returned(outcome, plan)
                } catch {
                    return .threw(String(describing: error))
                }
            }
            await gate.waitUntilSeen()
            group.cancelAll()
            await gate.resume()
            return await group.next() ?? .threw("group ended without a result")
        }

        guard case .returned(let outcome, _) = attempt else {
            XCTFail("A stopped scan must return partial results, not throw: \(attempt)")
            return
        }
        XCTAssertTrue(outcome.wasCancelled)
        XCTAssertFalse(outcome.files.isEmpty, "The in-memory outcome keeps the crawled records")
        let persisted = try await store.loadFileRecords(for: outcome.session.id)
        XCTAssertTrue(
            persisted.isEmpty,
            "A stopped scan must not block Stop on the bulk record write")
    }
}
