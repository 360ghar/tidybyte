import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Wave 1C hardening tests: ProcessRunner pipe draining, MemoryEngine rule
/// scoping and regret path keying, MoCleanScanner caches-root safety, and
/// CleanerRuleEngine project-aware matching.
final class ProcessMemoryScannerTests: XCTestCase {

    // MARK: - ProcessRunner

    func testProcessRunnerCapturesLargeOutputWithoutKillingChild() async {
        // ~300 KB of stdout, well past the 64 KB pipe buffer. The previous
        // implementation read the pipes only after the child exited, so a full
        // pipe buffer blocked (then killed) the child via the timeout.
        let script = "yes '0123456789abcdef' | head -c 300000"
        let result = await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", script],
            timeout: 20
        )
        XCTAssertEqual(result.exitCode, 0, "Child must complete normally instead of being killed for producing output")
        XCTAssertEqual(result.stdout.utf8.count, 300_000, "All large output should be captured")
        XCTAssertFalse(result.stderr.contains("timed out"))
    }

    func testProcessRunnerCapsRunawayOutputWithoutKillingChild() async {
        // 2 MB of output: the child must still finish (exit 0, not killed), with
        // captured output capped at 1 MB per stream plus a truncation note.
        let script = "yes '0123456789abcdef' | head -c 2000000"
        let result = await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", script],
            timeout: 20
        )
        XCTAssertEqual(result.exitCode, 0, "Child must complete normally instead of being killed for producing output")
        XCTAssertLessThan(result.stdout.utf8.count, 2_000_000, "Output over the cap must be truncated")
        XCTAssertGreaterThan(result.stdout.utf8.count, 1_000_000, "The first 1 MB of output should be captured")
        XCTAssertTrue(result.stdout.contains("output exceeded"), "A truncation note should be appended")
    }

    // MARK: - MemoryEngine: action-type scoping

    func testMemoryEngineNeverRuleScopedToActionType() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let fileURL = URL(fileURLWithPath: "/tmp/memory-scope/test-cache.bin")
        let record = FileRecord(scanSessionID: "scan-1", url: fileURL, sizeBytes: 1024)
        let filesByID = [record.id: record]

        // Learn a "never" rule from a moveToTrash decision.
        let action = PlannedAction(
            id: "action", planID: "plan", actionType: .moveToTrash,
            targets: [record.id], destination: nil, status: .approved,
            risk: .medium, confidence: 0.9, reason: "test",
            userDecision: .neverDoThisHere, executedAt: nil, findingID: nil
        )
        try await memory.learn(from: action, filesByID: filesByID)

        let rules = try await store.loadMemoryRules()
        XCTAssertEqual(rules.first?.actionType, .moveToTrash, "Learned rule must record its action type")

        // A moveToTrash candidate for the same directory IS suppressed.
        let trashRecommendation = Recommendation(
            id: "rec-trash", findingID: "finding", actionType: .moveToTrash,
            targetFileIDs: [record.id], confidence: 0.9, risk: .low,
            reason: "test", expectedBytesReclaimed: 1024,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let adjusted = try await memory.applyMemory(to: [trashRecommendation], filesByID: filesByID)
        XCTAssertEqual(adjusted[0].risk, .high)
        XCTAssertEqual(adjusted[0].actionType, .inspectOnly)
        XCTAssertLessThanOrEqual(adjusted[0].confidence, 0.55)

        // A tag candidate for the same file is NOT suppressed by the
        // moveToTrash-only never rule.
        let tagRecommendation = Recommendation(
            id: "rec-tag", findingID: "finding", actionType: .tag,
            targetFileIDs: [record.id], confidence: 0.9, risk: .low,
            reason: "test", expectedBytesReclaimed: 0,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let tagAdjusted = try await memory.applyMemory(to: [tagRecommendation], filesByID: filesByID)
        XCTAssertEqual(tagAdjusted[0].risk, .low)
        XCTAssertEqual(tagAdjusted[0].actionType, .tag)
        XCTAssertFalse(tagAdjusted[0].reason.contains("Memory rule applied"))
    }

    // MARK: - MemoryEngine: regret rules keyed by path

    func testMemoryEngineRegretRuleMatchesByPathAcrossScans() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let restoredPath = "/tmp/regret-fixture/recovered.pdf"

        // The restoredFileID from the old scan is a per-scan UUID that will never
        // match future scans; the rule must be keyed by the filesystem path.
        try await memory.recordRegret(
            operationLogID: "log-1",
            restoredFileID: "scan-1-file-uuid",
            reason: "Needed the file",
            restoredFilePath: restoredPath
        )

        let rules = try await store.loadMemoryRules()
        let regretRule = try XCTUnwrap(rules.first { $0.source == "regret" })
        XCTAssertEqual(regretRule.scopeType, "file")
        XCTAssertEqual(regretRule.scopeValue, restoredPath, "Regret rule must be keyed by the restored file path")

        // A later scan produces a fresh record (new UUID) for the same real path.
        let newRecord = FileRecord(scanSessionID: "scan-2", url: URL(fileURLWithPath: restoredPath), sizeBytes: 100)
        let recommendation = Recommendation(
            id: "rec", findingID: "finding", actionType: .moveToTrash,
            targetFileIDs: [newRecord.id], confidence: 0.9, risk: .low,
            reason: "test", expectedBytesReclaimed: 100,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let adjusted = try await memory.applyMemory(to: [recommendation], filesByID: [newRecord.id: newRecord])
        XCTAssertEqual(adjusted[0].risk, .high, "Regret rule should suppress cleanup of the regretted path")
        XCTAssertEqual(adjusted[0].actionType, .inspectOnly)
        XCTAssertTrue(adjusted[0].reason.contains("Memory rule applied"))

        // A different path in the same folder is not suppressed.
        let otherRecord = FileRecord(scanSessionID: "scan-2", url: URL(fileURLWithPath: "/tmp/regret-fixture/other.pdf"), sizeBytes: 100)
        let otherRecommendation = Recommendation(
            id: "rec-other", findingID: "finding", actionType: .moveToTrash,
            targetFileIDs: [otherRecord.id], confidence: 0.9, risk: .low,
            reason: "test", expectedBytesReclaimed: 100,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let otherAdjusted = try await memory.applyMemory(to: [otherRecommendation], filesByID: [otherRecord.id: otherRecord])
        XCTAssertEqual(otherAdjusted[0].risk, .low, "Regret rule must not suppress a different path")
        XCTAssertEqual(otherAdjusted[0].actionType, .moveToTrash)
    }

    func testMemoryEngineRegretRuleDerivesPathFromRestoredFileID() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let restoredPath = "/tmp/regret-fixture/path-only.pdf"
        // UndoManagerService falls back to the restore URL path when no file_id
        // is recorded; recordRegret must recognize it as a path.
        try await memory.recordRegret(
            operationLogID: "log-2",
            restoredFileID: restoredPath,
            reason: "Needed the file"
        )
        let rules = try await store.loadMemoryRules()
        let regretRule = try XCTUnwrap(rules.first { $0.source == "regret" })
        XCTAssertEqual(regretRule.scopeValue, restoredPath)
    }

    // MARK: - MoCleanScanner: never propose caches roots

    func testMoCleanScannerNeverProposesCachesRootDirectory() async throws {
        let home = try UserStoryFixtures.makeTemporaryDirectory(named: "CachesRoot")
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile("Library/Caches/com.example.app/cache.bin", in: home, data: Data(repeating: 1, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile("Library/Caches/other-app/blob.dat", in: home, data: Data(repeating: 2, count: 3_000_000))

        let scanner = MoCleanScanner(homeDirectoryOverride: home)
        let result = await scanner.scan(section: .userEssentials, sessionID: "scan")

        let cachesRoot = home.appendingPathComponent("Library/Caches", isDirectory: true).standardizedFileURL.path
        let targetPaths = Set(result.files.map(\.displayPath))
        XCTAssertFalse(targetPaths.contains(cachesRoot), "The caches root directory itself must never be proposed")
        XCTAssertFalse(result.findings.isEmpty, "Individual cache entries below the caches root should still be surfaced")
        for finding in result.findings {
            XCTAssertEqual(finding.severity, .low, "Individual user-level cache entries stay low risk")
            for id in finding.targetFileIDs {
                let path = try XCTUnwrap(result.files.first { $0.id == id }?.displayPath)
                XCTAssertTrue(path.hasPrefix(cachesRoot + "/"), "Findings must target entries below the caches root, not the root: \(path)")
            }
        }
        XCTAssertTrue(result.recommendations.allSatisfy { $0.actionType == .moveToTrash })
    }

    func testMoCleanScannerClassifiesWholeSystemCacheRootsAsMediumRisk() {
        let home = URL(fileURLWithPath: "/tmp/moclean-fake-home")
        XCTAssertEqual(MoCleanScanner.cacheEntryRisk(underRoot: "/Library/Caches", home: home), .medium)
        XCTAssertEqual(MoCleanScanner.cacheEntryRisk(underRoot: "/System/Library/Caches", home: home), .medium)
        XCTAssertEqual(MoCleanScanner.cacheEntryRisk(underRoot: "/tmp/moclean-fake-home/Library/Caches", home: home), .low)
    }

    // MARK: - CleanerRuleEngine: project-aware matching

    private func makeProject(root: URL, name: String = "demo") -> ProjectUnit {
        ProjectUnit(
            id: UUID().uuidString, name: name, rootURL: root, projectType: "Node",
            confidence: 0.95, lastActivityAt: nil,
            manifestFiles: [root.appendingPathComponent("package.json")],
            sourceFilesCount: 0, generatedFilesCount: 0, totalBytes: 2_000_000,
            reclaimableBytes: 2_000_000, status: .active
        )
    }

    func testRuleEngineDoesNotProposeBuildOutputsOutsideProjectRoot() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "RuleEngineNoProject")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try UserStoryFixtures.createDirectory("node_modules", in: root)
        _ = try UserStoryFixtures.writeFile("node_modules/pkg/index.js", in: root, data: Data(repeating: 1, count: 2_000_000))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, recommendations) = await engine.analyze(files: records, projects: [], sessionID: "scan")

        XCTAssertFalse(findings.contains { $0.category == .developerArtifact }, "Build outputs outside a detected project root must not be proposed")
        XCTAssertTrue(recommendations.isEmpty, "No cleanup should be proposed for an unrooted node_modules")
    }

    func testRuleEngineProposesBuildOutputsInsideProjectRoot() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "RuleEngineProject")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try UserStoryFixtures.writeFile("package.json", in: root, data: Data("{}".utf8))
        _ = try UserStoryFixtures.createDirectory("node_modules", in: root)
        _ = try UserStoryFixtures.writeFile("node_modules/pkg/index.js", in: root, data: Data(repeating: 1, count: 2_000_000))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [makeProject(root: root)], sessionID: "scan")

        XCTAssertTrue(findings.contains { $0.category == .developerArtifact }, "node_modules inside a detected project root should be proposed")
    }

    func testRuleEngineNodeModulesCacheOnlyMatchesInsideProjectRoot() async throws {
        let crawler = FileCrawler()
        let engine = CleanerRuleEngine()

        // Outside any project root: node_modules/.cache must not be proposed.
        let outside = try UserStoryFixtures.makeTemporaryDirectory(named: "RuleEngineNoProject")
        defer { try? FileManager.default.removeItem(at: outside) }
        _ = try UserStoryFixtures.createDirectory("node_modules/.cache", in: outside)
        _ = try UserStoryFixtures.writeFile("node_modules/.cache/blob.bin", in: outside, data: Data(repeating: 1, count: 2_000_000))
        let (outsideRecords, _) = await crawler.crawl(rootURLs: [outside], sessionID: "scan")
        let (outsideFindings, outsideRecs) = await engine.analyze(files: outsideRecords, projects: [], sessionID: "scan")
        XCTAssertFalse(outsideFindings.contains { $0.category == .cache || $0.category == .developerArtifact })
        XCTAssertTrue(outsideRecs.isEmpty, "node_modules/.cache outside a project root must not be proposed")

        // Inside a detected project root: node_modules/.cache is a legit cache.
        let inside = try UserStoryFixtures.makeTemporaryDirectory(named: "RuleEngineProject")
        defer { try? FileManager.default.removeItem(at: inside) }
        _ = try UserStoryFixtures.writeFile("package.json", in: inside, data: Data("{}".utf8))
        _ = try UserStoryFixtures.createDirectory("node_modules/.cache", in: inside)
        _ = try UserStoryFixtures.writeFile("node_modules/.cache/blob.bin", in: inside, data: Data(repeating: 1, count: 2_000_000))
        let (insideRecords, _) = await crawler.crawl(rootURLs: [inside], sessionID: "scan")
        let (insideFindings, _) = await engine.analyze(files: insideRecords, projects: [makeProject(root: inside)], sessionID: "scan")
        XCTAssertTrue(insideFindings.contains { $0.category == .cache }, "node_modules/.cache inside a project root should be proposed as cache")
    }

    func testRuleEngineNeverProposesProjectSourceManifestsOrCredentials() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "RuleEngineSource")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try UserStoryFixtures.writeFile("package.json", in: root, data: Data("{}".utf8))
        _ = try UserStoryFixtures.writeFile("src/main.swift", in: root, data: Data("print(\"hi\")\n".utf8))
        _ = try UserStoryFixtures.writeFile(".env", in: root, data: Data("TOKEN=secret".utf8))
        // A rebuildable cache next to them is fine to propose.
        _ = try UserStoryFixtures.createDirectory("Caches", in: root)
        _ = try UserStoryFixtures.writeFile("Caches/blob.bin", in: root, data: Data(repeating: 1, count: 2_000_000))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (_, recommendations) = await engine.analyze(files: records, projects: [], sessionID: "scan")

        let targetPaths = Set(
            recommendations.flatMap(\.targetFileIDs).compactMap { id in
                records.first { $0.id == id }?.displayPath
            }
        )
        XCTAssertFalse(targetPaths.contains { $0.hasSuffix("package.json") }, "Manifests must never be proposed")
        XCTAssertFalse(targetPaths.contains { $0.hasSuffix("main.swift") }, "Source files must never be proposed")
        XCTAssertFalse(targetPaths.contains { $0.hasSuffix(".env") }, "Credentials must never be proposed")
        XCTAssertTrue(targetPaths.contains { $0.hasSuffix("Caches") }, "Legit cache entries should still be proposed")
    }
}
