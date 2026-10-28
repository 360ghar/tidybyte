import Foundation
import SQLite3
@testable import MacOSCleanerCore
import XCTest

/// Wave 1B: privacy gating (localOnly/metadataOnly), volume-based space forecast,
/// fullDocumentAI content payload, and duplicate-placeholder exclusion.
final class PrivacyForecastTests: XCTestCase {

    // MARK: - Fix 1: Privacy gating of content extraction

    func testLocalOnlyScanProducesNoContentSummariesAndPersistsNothing() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "PrivacyLocalOnly")
        defer { try? FileManager.default.removeItem(at: root) }
        // A real text file with extractable content: without the privacy gate this
        // would produce a text preview summary.
        _ = try UserStoryFixtures.writeFile("Notes/meeting.txt", in: root, data: Data("Quarterly review, budget and roadmap".utf8))

        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("privacy.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)
        let orchestrator = ScanOrchestrator(store: store, memory: memory)

        let (outcome, _) = try await orchestrator.scan(
            mode: .selectedFolders,
            selectedFolders: [root.appendingPathComponent("Notes", isDirectory: true)],
            providerSettings: ProviderSettings(privacyMode: .localOnly),
            includeAI: false
        )

        XCTAssertEqual(outcome.session.status, .completed)
        XCTAssertTrue(outcome.contentSummaries.isEmpty,
                      "localOnly mode must produce zero content summaries (this array is what saveContentSummaries persists)")

        // Hard persistence check: the content_summaries table must contain no rows
        // after the localOnly scan.
        await store.close()
        var db: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("privacy.sqlite", isDirectory: false).path, &db) == SQLITE_OK else {
            XCTFail("Failed to open test database for row count")
            return
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM content_summaries", -1, &statement, nil) == SQLITE_OK else {
            XCTFail("Failed to prepare content_summaries count query")
            return
        }
        var count: Int = -1
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int64(statement, 0))
        }
        XCTAssertEqual(count, 0, "localOnly scan must persist zero content_summaries rows")
    }

    func testContentExtractorLocalOnlyExtractsNothing() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "ExtractorLocalOnly")
        defer { try? FileManager.default.removeItem(at: root) }
        let txtURL = try UserStoryFixtures.writeFile("doc.txt", in: root, data: Data("Invoice total 42 dollars".utf8))
        let pngURL = try UserStoryFixtures.writeFile("photo.png", in: root, data: Data(base64Encoded: Self.tinyPNGBase64) ?? Data())

        let extractor = ContentExtractor()
        let txtRecord = try await UserStoryFixtures.fileRecord(from: txtURL)
        let pngRecord = try await UserStoryFixtures.fileRecord(from: pngURL)
        let files: [FileRecord] = [txtRecord, pngRecord]
        let summaries = await extractor.summarize(files: files, privacyMode: .localOnly)
        XCTAssertTrue(summaries.isEmpty, "localOnly mode must not extract text, OCR, or any content summaries")
    }

    func testContentExtractorMetadataOnlyClassifiesWithoutFileContents() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "ExtractorMetadataOnly")
        defer { try? FileManager.default.removeItem(at: root) }
        let txtURL = try UserStoryFixtures.writeFile("doc.txt", in: root, data: Data("Invoice total 42 dollars".utf8))
        let pngURL = try UserStoryFixtures.writeFile("photo.png", in: root, data: Data(base64Encoded: Self.tinyPNGBase64) ?? Data())

        let extractor = ContentExtractor()
        let txtRecord = try await UserStoryFixtures.fileRecord(from: txtURL)
        let pngRecord = try await UserStoryFixtures.fileRecord(from: pngURL)
        let files: [FileRecord] = [txtRecord, pngRecord]

        let metadataOnly = await extractor.summarize(files: files, privacyMode: .metadataOnlyAI)
        XCTAssertFalse(metadataOnly.isEmpty, "Image metadata labels may still be produced in metadataOnly mode")
        let hasNoFileContents: Bool = metadataOnly.allSatisfy { (summary: ContentSummary) in
            summary.textPreview == nil && summary.ocrText == nil
        }
        XCTAssertTrue(hasNoFileContents, "metadataOnly mode must never extract text or OCR content")
        XCTAssertFalse(metadataOnly.contains { $0.fileID == files[0].id },
                       "Text file must produce no summary in metadataOnly mode (no content read)")

        // Contrast: the same text file DOES produce a preview when content extraction is permitted.
        let snippets = await extractor.summarize(files: [files[0]], privacyMode: .snippetsAI)
        XCTAssertEqual(snippets.count, 1)
        XCTAssertNotNil(snippets.first?.textPreview, "snippetsAI mode may read text content")
    }

    // MARK: - Fix 3: AIGateway fullDocumentAI payload and cancellation

    func testFullDocumentAIPayloadIncludesExtractedContent() async throws {
        let (gateway, body) = try makeGatewayWithRequestCapture()
        try await withGatewayAPIKey {
            let file = FileRecord(scanSessionID: "scan", url: URL(fileURLWithPath: "/tmp/notes.txt"), sizeBytes: 10)
            let findings = [
                Finding(
                    id: "f1", scanSessionID: "scan", category: .largeFile, severity: .low,
                    confidence: 0.9, bytesReclaimable: 10, summary: "large file",
                    evidence: [:], targetFileIDs: [file.id]
                )
            ]
            let summaries = [
                ContentSummary(
                    fileID: file.id, textPreview: "preview-secret-content", ocrText: nil,
                    language: nil, detectedTopics: [], imageLabels: [], videoLabels: [],
                    privacyLevel: .fullDocumentAI
                )
            ]

            let settings = ProviderSettings(privacyMode: .fullDocumentAI)
            MockURLProtocol.mockResponse = { request in
                body.wrapped = Self.capturedBody(for: request)
                return (Self.successEnvelopeData(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            defer { MockURLProtocol.mockResponse = nil }

            let recommendations = try await gateway.classify(findings: findings, filesByID: [file.id: file], settings: settings, contentSummaries: summaries)
            XCTAssertTrue(recommendations.isEmpty, "Empty recommendation list is a valid mock response")

            let requestBody = body.wrapped
            XCTAssertFalse(requestBody.isEmpty, "Mock must capture the request body")
            XCTAssertTrue(requestBody.contains("preview-secret-content"),
                          "fullDocumentAI request must include extracted file content")
            XCTAssertTrue(requestBody.contains("snippet"), "fullDocumentAI request must carry snippet fields")
        }
    }

    func testMetadataOnlyAIPayloadExcludesFileContents() async throws {
        let (gateway, body) = try makeGatewayWithRequestCapture()
        try await withGatewayAPIKey {
            let file = FileRecord(scanSessionID: "scan", url: URL(fileURLWithPath: "/tmp/notes.txt"), sizeBytes: 10)
            let findings = [
                Finding(
                    id: "f1", scanSessionID: "scan", category: .largeFile, severity: .low,
                    confidence: 0.9, bytesReclaimable: 10, summary: "large file",
                    evidence: [:], targetFileIDs: [file.id]
                )
            ]
            let summaries = [
                ContentSummary(
                    fileID: file.id, textPreview: "preview-secret-content", ocrText: "ocr-secret-content",
                    language: nil, detectedTopics: [], imageLabels: [], videoLabels: [],
                    privacyLevel: .metadataOnlyAI
                )
            ]

            MockURLProtocol.mockResponse = { request in
                body.wrapped = Self.capturedBody(for: request)
                return (Self.successEnvelopeData(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            defer { MockURLProtocol.mockResponse = nil }

            _ = try await gateway.classify(findings: findings, filesByID: [file.id: file], settings: ProviderSettings(privacyMode: .metadataOnlyAI), contentSummaries: summaries)

            let requestBody = body.wrapped
            XCTAssertFalse(requestBody.isEmpty, "Mock must capture the request body")
            XCTAssertFalse(requestBody.contains("preview-secret-content"),
                           "metadataOnlyAI request must not include text content")
            XCTAssertFalse(requestBody.contains("ocr-secret-content"),
                           "metadataOnlyAI request must not include OCR content")
            XCTAssertFalse(requestBody.contains("snippet"), "metadataOnlyAI request must not carry snippet fields")
        }
    }

    func testAIGatewayCancellationMapsToTypedCancellationError() async throws {
        try await withGatewayAPIKey {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [CancellationFailingURLProtocol.self]
            let session = URLSession(configuration: config)
            let gateway = AIGateway(keychain: TestFixtures.privacyKeychain, session: session)

            do {
                _ = try await gateway.classify(
                    findings: [],
                    filesByID: [:],
                    settings: ProviderSettings(privacyMode: .metadataOnlyAI)
                )
                XCTFail("Cancelled request must throw")
            } catch is CancellationError {
                // Expected: URLSession cancellation surfaces as a typed CancellationError
                // instead of being retried and misreported as a generic failure.
            } catch let error as AIGatewayError {
                XCTFail("Cancellation must not be reported as gateway failure: \(error)")
            } catch {
                XCTFail("Cancellation must not be swallowed or misreported: \(error)")
            }
        }
    }

    // MARK: - Fix 2: SpaceForecaster volume-based basis

    func testSpaceForecasterUsesVolumeUsageNotScannedBytes() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "ForecastVolumeBasis")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("forecast.sqlite", isDirectory: false))

        // Scanned bytes are tiny (2 GB total) while the volume is 1 TB with 400 GB
        // available (600 GB used). The old implementation extrapolated scanned bytes
        // against capacity; the fixed one must project from ACTUAL volume usage.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        try await store.saveStorageSnapshot(StorageSnapshot(
            id: "s1", createdAt: yesterday, totalBytes: 1_000_000_000,
            bytesByCategory: [:], bytesByRootPath: [:], bytesByProject: [:], removedBytesThroughApp: 0
        ))
        try await store.saveStorageSnapshot(StorageSnapshot(
            id: "s2", createdAt: Date(), totalBytes: 2_000_000_000,
            bytesByCategory: [:], bytesByRootPath: [:], bytesByProject: [:], removedBytesThroughApp: 0
        ))

        let forecaster = SpaceForecaster(store: store)
        let forecast = try await forecaster.forecast(capacity: 1_000_000_000_000, availableBytes: 400_000_000_000)
        let unwrapped = try XCTUnwrap(forecast, "Two snapshots with growth must produce a forecast")
        XCTAssertEqual(unwrapped.dailyGrowthRate, 1_000_000_000)
        // 600 GB used, 1 GB/day growth: 80% = 200 days, 90% = 300 days, 95% = 350 days.
        // Scanned-bytes math would report ~948 days; volume-based math reports 350.
        XCTAssertEqual(unwrapped.daysUntil80PercentFull, 200, "80% projection must use actual volume usage")
        XCTAssertEqual(unwrapped.daysUntil90PercentFull, 300, "90% projection must use actual volume usage")
        XCTAssertEqual(unwrapped.daysUntil95PercentFull, 350, "95% projection must use actual volume usage")
        XCTAssertFalse(unwrapped.message.isEmpty)
    }

    func testSpaceForecasterVolumeURLReadsRealVolumeCapacity() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "ForecastVolumeURL")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("forecast.sqlite", isDirectory: false))

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        try await store.saveStorageSnapshot(StorageSnapshot(
            id: "s1", createdAt: yesterday, totalBytes: 100_000_000_000,
            bytesByCategory: [:], bytesByRootPath: [:], bytesByProject: [:], removedBytesThroughApp: 0
        ))
        try await store.saveStorageSnapshot(StorageSnapshot(
            id: "s2", createdAt: Date(), totalBytes: 101_000_000_000,
            bytesByCategory: [:], bytesByRootPath: [:], bytesByProject: [:], removedBytesThroughApp: 0
        ))

        let forecaster = SpaceForecaster(store: store)
        let forecast = try await forecaster.forecast(volumeURL: FileManager.default.homeDirectoryForCurrentUser)
        let unwrapped = try XCTUnwrap(forecast, "Home volume resource values must yield a forecast")
        XCTAssertEqual(unwrapped.dailyGrowthRate, 1_000_000_000, "Growth rate comes from snapshot history")
        XCTAssertGreaterThanOrEqual(unwrapped.daysUntil80PercentFull ?? Int.max, 0)
    }

    // MARK: - Fix 4: DuplicateDetector excludes cloud placeholders

    func testDuplicateDetectorExcludesCloudPlaceholders() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "DupPlaceholder")
        defer { try? FileManager.default.removeItem(at: root) }
        let aURL = try UserStoryFixtures.writeFile("a.txt", in: root, data: Data("dup-payload".utf8))
        let bURL = try UserStoryFixtures.writeFile("b.txt", in: root, data: Data("dup-payload".utf8))

        let size: Int64 = Int64((try? Data(contentsOf: aURL).count) ?? 11)
        let realA = FileRecord(scanSessionID: "scan", url: aURL, sizeBytes: size)
        let realB = FileRecord(scanSessionID: "scan", url: bURL, sizeBytes: size)

        // Control: two real identical files ARE flagged as duplicates.
        let detector = DuplicateDetector()
        let control = try await detector.analyze(files: [realA, realB], sessionID: "scan")
        XCTAssertFalse(control.findings.isEmpty, "Real duplicates must still be detected")
        XCTAssertFalse(control.recommendations.isEmpty)

        // A cloud placeholder with the same size must never join a duplicate group:
        // it has no local content and must never be proposed for trashing.
        let placeholder = FileRecord(
            id: "ph", scanSessionID: "scan", source: .iCloudLocal, url: URL(fileURLWithPath: "/tmp/nonexistent/placeholder.txt"),
            displayPath: "/tmp/nonexistent/placeholder.txt", fileName: "placeholder.txt", fileExtension: "txt",
            utiDescription: nil, kind: .regularFile, sizeBytes: size, createdAt: nil, modifiedAt: nil,
            lastOpenedAt: nil, owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
            isPackage: false, isCloudPlaceholder: true, cloudProvider: "iCloud", finderTags: [],
            spotlightMetadata: [:], riskFlags: [], identity: FileIdentity(deviceIdentifier: nil, inodeIdentifier: nil, resourceIdentifier: nil),
            capabilities: []
        )

        let result = try await detector.analyze(files: [realA, placeholder], sessionID: "scan")
        XCTAssertTrue(result.findings.isEmpty, "Placeholder files must never be proposed as duplicates")
        XCTAssertTrue(result.recommendations.isEmpty)
        XCTAssertTrue(result.fingerprints.isEmpty, "Placeholder files must never be hashed")
        XCTAssertTrue(result.edges.isEmpty)
    }

    func testDuplicateDetectorPlaceholderPredicate() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "DupPredicate")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = try UserStoryFixtures.writeFile("real.txt", in: root, data: Data("hello".utf8))

        // Real file on disk: not a placeholder (resource-value fallback reads the file).
        let real = FileRecord(scanSessionID: "scan", url: fileURL, sizeBytes: 5)
        XCTAssertFalse(DuplicateDetector.isCloudPlaceholder(real), "A local file must not be treated as a placeholder")

        // Flag-based path: the crawler marks ubiquitous files whose content is not
        // downloaded as placeholders. The resource-value fallback cannot be faked
        // without a real iCloud file, so the flag path is exercised directly.
        let flagged = FileRecord(
            id: "ph", scanSessionID: "scan", source: .iCloudLocal, url: URL(fileURLWithPath: "/tmp/nonexistent/placeholder.txt"),
            displayPath: "/tmp/nonexistent/placeholder.txt", fileName: "placeholder.txt", fileExtension: "txt",
            utiDescription: nil, kind: .regularFile, sizeBytes: 5, createdAt: nil, modifiedAt: nil,
            lastOpenedAt: nil, owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
            isPackage: false, isCloudPlaceholder: true, cloudProvider: "iCloud", finderTags: [],
            spotlightMetadata: [:], riskFlags: [], identity: FileIdentity(deviceIdentifier: nil, inodeIdentifier: nil, resourceIdentifier: nil),
            capabilities: []
        )
        XCTAssertTrue(DuplicateDetector.isCloudPlaceholder(flagged), "Crawler-flagged placeholder must be excluded")
    }

    // MARK: - Helpers

    private static let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private static func successEnvelopeData() -> Data {
        Data(#"{"choices":[{"message":{"content":"{\"recommendations\":[]}"}}]}"#.utf8)
    }

    /// Reads the POST body at URLProtocol time. `request.httpBody` can be nil
    /// there because URLSession may deliver the body as an `httpBodyStream`.
    private static func capturedBody(for request: URLRequest) -> String {
        if let httpBody = request.httpBody, !httpBody.isEmpty {
            return String(data: httpBody, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else {
            return ""
        }
        stream.open()
        defer { stream.close() }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&chunk, maxLength: chunk.count)
            guard read > 0 else { break }
            buffer.append(chunk, count: read)
        }
        return String(data: buffer, encoding: .utf8) ?? ""
    }

    private func gatewayKeychainSave() async throws {
        try await TestFixtures.privacyKeychain.saveAPIKey("test-key-for-privacy-tests")
    }

    private func gatewayKeychainDelete() async throws {
        try? await TestFixtures.privacyKeychain.deleteAPIKey()
    }

    /// Saves a test API key for the duration of `body` and always removes it
    /// afterwards (async defer is not allowed, so cleanup is explicit).
    private func withGatewayAPIKey<T>(_ body: () async throws -> T) async throws -> T {
        try await gatewayKeychainSave()
        do {
            let result = try await body()
            try? await gatewayKeychainDelete()
            return result
        } catch {
            try? await gatewayKeychainDelete()
            throw error
        }
    }

    private func makeGatewayWithRequestCapture() throws -> (AIGateway, RequestBox) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let box = RequestBox()
        return (AIGateway(keychain: TestFixtures.privacyKeychain, session: session), box)
    }
}

/// Thread-safe box for capturing the request body written by the mock URL protocol.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    var wrapped: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

/// URL protocol that fails every request with a cancelled error, simulating task cancellation.
private final class CancellationFailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}
