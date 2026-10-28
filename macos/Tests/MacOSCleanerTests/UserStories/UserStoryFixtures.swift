import Foundation
@testable import MacOSCleanerCore

enum UserStoryFixtures {
    static func makeTemporaryDirectory(named prefix: String = "UserStory") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleaner-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeFile(
        _ relativePath: String,
        in root: URL,
        data: Data = Data("fixture".utf8),
        modifiedDaysAgo: Int? = nil
    ) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modifiedDaysAgo,
           let date = Calendar.current.date(byAdding: .day, value: -modifiedDaysAgo, to: Date()) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    static func createDirectory(_ relativePath: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileRecord(from url: URL, sessionID: String = "scan") async throws -> FileRecord {
        let root = url.deletingLastPathComponent()
        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: sessionID)
        guard let record = records.first(where: { $0.url == url.standardizedFileURL }) else {
            throw FixtureError.missingRecord
        }
        return record
    }
}

private enum FixtureError: Error {
    case missingRecord
}
