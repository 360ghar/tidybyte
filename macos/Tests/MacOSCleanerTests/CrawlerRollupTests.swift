import XCTest
@testable import MacOSCleanerAppKit
@testable import MacOSCleanerCore

/// The crawler summarizes bulk folders so a large home folder does not hold
/// millions of records in memory. Sizes must stay honest while it does.
final class CrawlerRollupTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = try TestFixtures.makeTemporaryDirectory(named: "CrawlerRollup-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, bytes: Int, daysAgo: Int? = nil) throws {
        _ = try UserStoryFixtures.writeFile(path, in: root, data: Data(repeating: 7, count: bytes), modifiedDaysAgo: daysAgo)
    }

    private func crawl(maxRecords: Int = FileCrawler.defaultMaxRecords) async -> [FileRecord] {
        await FileCrawler(maxRecords: maxRecords).crawl(rootURLs: [root], sessionID: "rollup").0
    }

    private func record(_ files: [FileRecord], at relative: String) -> FileRecord? {
        let path = root.appendingPathComponent(relative).standardizedFileURL.path
        return files.first { $0.displayPath == path }
    }

    func testBulkFolderIsOneRecordWithTheTotalOfItsContents() async throws {
        try write("Project/package.json", bytes: 2)
        try write("Project/node_modules/left-pad/index.js", bytes: 100)
        try write("Project/node_modules/react.js", bytes: 50)
        try write("Project/src/main.js", bytes: 10)

        let files = await crawl()
        let modules = try XCTUnwrap(record(files, at: "Project/node_modules"))

        XCTAssertEqual(modules.sizeBytes, 150)
        XCTAssertEqual(modules.rolledUpItemCount, 3, "left-pad, left-pad/index.js, and react.js")
        XCTAssertFalse(files.contains { $0.displayPath.hasPrefix(modules.displayPath + "/") })
        XCTAssertNotNil(record(files, at: "Project/src/main.js"), "Source files keep their own records")
        XCTAssertNil(record(files, at: "Project/src")?.rolledUpItemCount)
    }

    func testCacheFolderInsideABulkFolderKeepsItsOwnRecord() async throws {
        try write("Project/package.json", bytes: 2)
        try write("Project/node_modules/react.js", bytes: 50)
        try write("Project/node_modules/.cache/babel/chunk.bin", bytes: 1_000)

        let files = await crawl()
        let modules = try XCTUnwrap(record(files, at: "Project/node_modules"))
        let cache = try XCTUnwrap(record(files, at: "Project/node_modules/.cache"))

        XCTAssertEqual(modules.sizeBytes, 50, "The cache folder's bytes are not counted twice")
        XCTAssertEqual(cache.sizeBytes, 1_000)
        XCTAssertEqual(cache.rolledUpItemCount, 2)
        let index = MoCleanScanner.buildSubtreeByteIndex(files: files)
        XCTAssertEqual(index[modules.displayPath], 1_050)
        XCTAssertEqual(ExploreSubtreeIndex.totals(files: files)[modules.displayPath], 1_050)
    }

    func testEachCacheEntryIsOneRecord() async throws {
        try write("Library/Caches/com.example.client/one.bin", bytes: 200)
        try write("Library/Caches/com.example.client/nested/two.bin", bytes: 300)
        try write("Library/Caches/loose.db", bytes: 40)

        let files = await crawl()
        let entry = try XCTUnwrap(record(files, at: "Library/Caches/com.example.client"))

        XCTAssertEqual(entry.sizeBytes, 500)
        XCTAssertEqual(entry.rolledUpItemCount, 3)
        XCTAssertNil(record(files, at: "Library/Caches/com.example.client/one.bin"))
        XCTAssertEqual(record(files, at: "Library/Caches/loose.db")?.sizeBytes, 40, "Files in the cache folder itself stay")
        XCTAssertEqual(ExploreSubtreeIndex.totals(files: files)[root.appendingPathComponent("Library/Caches").path], 540)
    }

    func testSummarizedFolderCarriesTheNewestChangeInside() async throws {
        try write("Project/node_modules/old.js", bytes: 1, daysAgo: 90)
        try write("Project/node_modules/new.js", bytes: 1)
        let modulesURL = root.appendingPathComponent("Project/node_modules")
        let longAgo = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -90, to: Date()))
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: modulesURL.path)

        let files = await crawl()
        let modules = try XCTUnwrap(record(files, at: "Project/node_modules"))

        let modified = try XCTUnwrap(modules.modifiedAt)
        XCTAssertLessThan(abs(modified.timeIntervalSinceNow), 3_600, "A folder with a new file inside is not old")
    }

    func testRecordBudgetSummarizesLaterFoldersAndKeepsTheTotal() async throws {
        for folder in 0..<6 {
            for file in 0..<5 {
                try write("Folder\(folder)/Sub/file\(file).bin", bytes: 10)
            }
        }

        let unbounded = await crawl()
        let bounded = await crawl(maxRecords: 8)

        XCTAssertEqual(unbounded.filter { $0.rolledUpItemCount != nil }.count, 0)
        XCTAssertLessThan(bounded.count, unbounded.count)
        XCTAssertGreaterThan(bounded.filter { $0.rolledUpItemCount != nil }.count, 0)
        let total = { (files: [FileRecord]) in files.reduce(Int64(0)) { $0 + $1.sizeBytes } }
        XCTAssertEqual(total(bounded), total(unbounded), "Summarized folders keep every byte")
        XCTAssertEqual(total(bounded), 300)
    }

    func testBuildFolderIsSummarizedOnlyBesideABuildManifest() async throws {
        try write("App/pubspec.yaml", bytes: 2)
        try write("App/build/ios/Runner.o", bytes: 70)
        try write("Notes/README.md", bytes: 2)
        try write("Notes/build/plan.pdf", bytes: 30)

        let files = await crawl()

        XCTAssertEqual(record(files, at: "App/build")?.rolledUpItemCount, 2)
        XCTAssertEqual(record(files, at: "App/build")?.sizeBytes, 70)
        XCTAssertNil(record(files, at: "Notes/build")?.rolledUpItemCount, "A README does not make a build project")
        XCTAssertEqual(record(files, at: "Notes/build/plan.pdf")?.sizeBytes, 30)
    }

    func testHardLinkedFilesAddNothingToASummarizedFolder() async throws {
        try write("Project/package.json", bytes: 2)
        try write("Project/node_modules/.pnpm/pkg/index.js", bytes: 100)
        try write("Project/node_modules/own.js", bytes: 40)
        try write("Store/pkg-index.js", bytes: 100)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Store/pkg-index.js"))
        try FileManager.default.linkItem(
            at: root.appendingPathComponent("Project/node_modules/.pnpm/pkg/index.js"),
            to: root.appendingPathComponent("Store/pkg-index.js"))

        let files = await crawl()

        let modules = try XCTUnwrap(record(files, at: "Project/node_modules"))
        XCTAssertEqual(modules.sizeBytes, 40, "Trashing a hard-linked file frees nothing")
        XCTAssertEqual(modules.rolledUpItemCount, 4, ".pnpm, pkg, index.js, and own.js")
    }

    func testLooseFilesPastTheBudgetFoldIntoTheirFolder() async throws {
        for file in 0..<20 { try write("Dump/file\(file).bin", bytes: 10) }

        let unbounded = await crawl()
        let bounded = await crawl(maxRecords: 6)

        XCTAssertLessThan(bounded.count, 10, "The budget is a hard cap")
        let dump = try XCTUnwrap(record(bounded, at: "Dump"))
        XCTAssertGreaterThan(dump.rolledUpItemCount ?? 0, 0)
        let total = { (files: [FileRecord]) in files.reduce(Int64(0)) { $0 + $1.sizeBytes } }
        XCTAssertEqual(total(bounded), total(unbounded), "Folded files keep every byte")
        XCTAssertEqual(total(bounded), 200)
    }

    func testLargeFilesKeepTheirRecordInsideSummarizedFoldersAndPastTheBudget() async throws {
        try write("App/package.json", bytes: 2)
        try write("App/build/small.o", bytes: 10)
        try write("Dump/note.txt", bytes: 5)
        for name in ["App/build/render.mov", "Dump/big.bin"] {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(FileCrawler.largeFileBytes))
            try handle.close()
        }

        let files = await crawl(maxRecords: 3)

        XCTAssertEqual(record(files, at: "App/build/render.mov")?.sizeBytes, FileCrawler.largeFileBytes)
        XCTAssertEqual(record(files, at: "Dump/big.bin")?.sizeBytes, FileCrawler.largeFileBytes)
        XCTAssertEqual(record(files, at: "App/build")?.sizeBytes, 10, "The large file is not counted twice")
    }

    func testPersonalFoldersAreCrawledBeforeLibraryAndToolFolders() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let names = ["Library", ".gradle", "Downloads", "Documents"]
        let ordered = names.map { home.appendingPathComponent($0) }.sorted { FileCrawler.crawlOrder($0) < FileCrawler.crawlOrder($1) }
        XCTAssertEqual(ordered.last?.lastPathComponent, "Library")
        XCTAssertEqual(ordered.dropLast().last?.lastPathComponent, ".gradle")
    }

    func testOnlySpecificFolderNamesAreSummarized() {
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("code/app/node_modules")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("code/app/.git")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("Library/Developer/Xcode/DerivedData")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("Library/Caches/com.apple.Safari")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent(".cache/pip")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/ABC-123")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/iPhone 26.0")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("Library/pnpm/store")))
        XCTAssertTrue(FileCrawler.rollsUp(home.appendingPathComponent("site/.runtime/pnpm-store")))
        // Personal folders and tool homes whose cache folders are candidates of their own.
        XCTAssertFalse(FileCrawler.rollsUp(home.appendingPathComponent("Documents/Pods")))
        XCTAssertFalse(FileCrawler.rollsUp(home.appendingPathComponent("Documents/build")))
        XCTAssertFalse(FileCrawler.rollsUp(home.appendingPathComponent(".gradle")))
        XCTAssertFalse(FileCrawler.rollsUp(home.appendingPathComponent("Library/Caches")))
        XCTAssertFalse(FileCrawler.rollsUp(home.appendingPathComponent("Pictures/Devices")))
        XCTAssertFalse(FileCrawler.rollsUp(home.appendingPathComponent("Documents/store")))
    }
}
