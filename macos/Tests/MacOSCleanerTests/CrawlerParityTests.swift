import XCTest
@testable import MacOSCleanerCore

final class CrawlerParityTests: XCTestCase {
    /// The fast crawler must see exactly what the old one saw.
    func testFastCrawlerMatchesLegacyCrawler() async throws {
        let root = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        for path in ["a/b/c.txt", "a/d.bin", "Tool.app/Contents/MacOS/tool", ".ssh/id_rsa", "top.txt", "e/f/g/h.log"] {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: path.count * 100).write(to: url)
        }
        try fm.linkItem(at: root.appendingPathComponent("a/d.bin"), to: root.appendingPathComponent("a/hard.bin"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("a"))

        let (fast, fastErrors) = await FileCrawler().crawl(rootURLs: [root], sessionID: "s")
        let (legacy, legacyErrors) = await LegacyFileCrawlerReference().crawl(rootURLs: [root], sessionID: "s")

        XCTAssertEqual(fastErrors, legacyErrors)
        XCTAssertEqual(fast.map(\.displayPath), legacy.map(\.displayPath))
        for (new, old) in zip(fast, legacy) {
            XCTAssertEqual(new.id, old.id, new.displayPath)
            XCTAssertEqual(new.kind, old.kind, new.displayPath)
            XCTAssertEqual(new.sizeBytes, old.sizeBytes, new.displayPath)
            XCTAssertEqual(new.identity.inodeIdentifier, old.identity.inodeIdentifier, new.displayPath)
            XCTAssertEqual(new.identity.deviceIdentifier, old.identity.deviceIdentifier, new.displayPath)
            XCTAssertEqual(new.riskFlags, old.riskFlags, new.displayPath)
            XCTAssertEqual(new.isPackage, old.isPackage, new.displayPath)
        }
        XCTAssertEqual(fast.first { $0.fileName == "hard.bin" }?.linkCount, 2)

        // A chosen package root is entered; a symlink root is recorded, never followed.
        for (chosen, count) in [("Tool.app", 4), ("link", 1)] {
            let url = root.appendingPathComponent(chosen)
            let (fastRoot, _) = await FileCrawler().crawl(rootURLs: [url], sessionID: "s")
            let (legacyRoot, _) = await LegacyFileCrawlerReference().crawl(rootURLs: [url], sessionID: "s")
            XCTAssertEqual(fastRoot.count, count, chosen)
            XCTAssertEqual(fastRoot.map(\.displayPath), legacyRoot.map(\.displayPath))
        }
    }

    /// Opt-in: TIDYBYTE_BENCH_ROOTS="/Applications:/usr/share" swift test -c release --filter CrawlerParityTests
    /// Read-only. Reports both crawlers' times on real folders.
    func testBenchmarkAgainstLegacyCrawler() async throws {
        guard let roots = ProcessInfo.processInfo.environment["TIDYBYTE_BENCH_ROOTS"] else {
            throw XCTSkip("Set TIDYBYTE_BENCH_ROOTS to run the crawler benchmark")
        }
        let urls = roots.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        let clock = ContinuousClock()
        var fastCount = 0
        var legacyCount = 0
        // Warm the file-system cache first so neither crawler pays for cold reads.
        _ = await FileCrawler().crawl(rootURLs: urls, sessionID: "warm")
        let legacyTime = await clock.measure {
            legacyCount = await LegacyFileCrawlerReference().crawl(rootURLs: urls, sessionID: "b").0.count
        }
        let fastTime = await clock.measure { fastCount = await FileCrawler().crawl(rootURLs: urls, sessionID: "b").0.count }
        print("BENCH legacy \(legacyCount) items in \(legacyTime); fast \(fastCount) items in \(fastTime)")
        XCTAssertEqual(fastCount, legacyCount)
    }
}

final class ReclaimableBytesTests: XCTestCase {
    func testClonesAndHardLinksFreeNothingAlone() async throws {
        let root = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.bin")
        try Data(repeating: 9, count: 4 * 1_048_576).write(to: original)
        let clone = root.appendingPathComponent("clone.bin")
        guard clonefile(original.path, clone.path, 0) == 0 else { throw XCTSkip("Temp volume is not APFS") }
        let link = root.appendingPathComponent("link.bin")
        try FileManager.default.linkItem(at: original, to: link)

        let (records, _) = await FileCrawler().crawl(rootURLs: [root], sessionID: "s")
        func size(_ name: String) -> Int64? {
            records.first { $0.fileName == name }.map { ReclaimableBytes.size(of: $0) }
        }
        XCTAssertEqual(size("clone.bin"), 0, "A clone shares every block with the original")
        XCTAssertEqual(size("link.bin"), 0, "One of two hard links frees nothing")
        XCTAssertEqual(size("original.bin"), 0, "The original now has a second link")
        XCTAssertEqual(records.first { $0.fileName == "clone.bin" }?.sizeBytes, 4 * 1_048_576)
    }
}
