import Foundation
@testable import MacOSCleanerCore
import XCTest

final class MacOSCleanerTests: XCTestCase {
    func testSafetyAuditorRejectsProtectedEnvFileTrash() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let envURL = root.appendingPathComponent(".env", isDirectory: false)
        try Data("SECRET=1".utf8).write(to: envURL)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let envRecord = try XCTUnwrap(records.first { $0.url == envURL.standardizedFileURL })
        XCTAssertTrue(envRecord.riskFlags.contains(.protectedFile))

        let action = PlannedAction(
            id: "action",
            planID: "plan",
            actionType: .moveToTrash,
            targets: [envRecord.id],
            destination: nil,
            status: .approved,
            risk: .medium,
            confidence: 0.9,
            reason: "test",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )
        let auditor = SafetyAuditor()
        do {
            _ = try await auditor.audit(action: action, filesByID: [envRecord.id: envRecord])
            XCTFail("Expected protected .env file to be rejected.")
        } catch let error as SafetyAuditError {
            guard case .unsafePath = error else {
                XCTFail("Unexpected safety error: \(error)")
                return
            }
        }
    }

    func testDuplicateDetectorRequiresFullHashBeforeRecommendation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("duplicate-payload".utf8).write(to: root.appendingPathComponent("a.txt", isDirectory: false))
        try Data("duplicate-payload".utf8).write(to: root.appendingPathComponent("b.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(files: records, sessionID: "scan")

        XCTAssertEqual(analysis.findings.count, 1)
        XCTAssertEqual(analysis.recommendations.count, 1)
        XCTAssertEqual(analysis.recommendations.first?.targetFileIDs.count, 1)
        XCTAssertEqual(analysis.fingerprints.filter { $0.fullHash != nil }.count, 2)
    }

    func testDeveloperArtifactPlanProtectsManifest() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("App", isDirectory: true)
        let nodeModules = project.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json", isDirectory: false))
        try Data(repeating: 1, count: 2048).write(to: nodeModules.appendingPathComponent("package.bin", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let projects = await ProjectDetector().detectProjects(in: records)
        let (findings, recommendations) = await CleanerRuleEngine().analyze(files: records, projects: projects, sessionID: "scan")

        XCTAssertTrue(findings.contains { $0.category == .developerArtifact })
        let packageRecord = try XCTUnwrap(records.first { $0.fileName == "package.json" })
        XCTAssertFalse(recommendations.flatMap(\.targetFileIDs).contains(packageRecord.id))
        XCTAssertTrue(recommendations.contains { $0.actionType == .moveToTrash && $0.risk == .medium })
    }

    func testSelectedFolderScanDoesNotIncludeGlobalPackageManagerCleanup() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Caches/App", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2_000_000).write(to: cache.appendingPathComponent("cache.bin", isDirectory: false))

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let orchestrator = ScanOrchestrator(store: store, memory: memory)

        let (outcome, scanPlan) = try await orchestrator.scan(
            mode: .selectedFolders,
            selectedFolders: [root],
            providerSettings: ProviderSettings(),
            includeAI: false
        )

        let packageCandidates = outcome.packageCandidates
        XCTAssertFalse(scanPlan.actions.contains { $0.actionType == .runPackageManagerCleanup })
        XCTAssertTrue(packageCandidates.isEmpty)
    }

    func testCodingAgentLogsAreCandidatesButConfigStaysProtected() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codexRoot = root.appendingPathComponent(".codex", isDirectory: true)
        let logs = codexRoot.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: logs.appendingPathComponent("session.log", isDirectory: false))
        try Data("token".utf8).write(to: codexRoot.appendingPathComponent("auth.json", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let logsRecord = try XCTUnwrap(records.first { $0.url == logs.standardizedFileURL })
        let authRecord = try XCTUnwrap(records.first { $0.fileName == "auth.json" })
        XCTAssertFalse(logsRecord.riskFlags.contains(.protectedDirectory))
        XCTAssertTrue(authRecord.riskFlags.contains(.codingAgentMemoryOrConfig))

        let (findings, recommendations) = await CleanerRuleEngine().analyze(files: records, projects: [], sessionID: "scan")
        XCTAssertTrue(findings.contains { $0.category == .codingAgentArtifact })
        XCTAssertTrue(recommendations.contains { $0.targetFileIDs.contains(logsRecord.id) && $0.actionType == .archive })
        XCTAssertFalse(recommendations.flatMap(\.targetFileIDs).contains(authRecord.id))
    }

    func testSQLiteStoreRoundTripsScanRecords() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("MacOSCleaner-\(UUID().uuidString).sqlite", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let store = try SQLiteStore(databaseURL: databaseURL)
        let session = ScanSession(scanType: .selectedFolders, rootURLs: [databaseURL.deletingLastPathComponent()], permissionsSnapshot: "test")
        let record = FileRecord(
            scanSessionID: session.id,
            source: .local,
            url: databaseURL,
            displayPath: databaseURL.path,
            fileName: databaseURL.lastPathComponent,
            fileExtension: "sqlite",
            utiDescription: nil,
            kind: .regularFile,
            sizeBytes: 42,
            createdAt: nil,
            modifiedAt: nil,
            lastOpenedAt: nil,
            owner: nil,
            permissions: nil,
            isSymlink: false,
            symlinkTarget: nil,
            isPackage: false,
            isCloudPlaceholder: false,
            cloudProvider: nil,
            finderTags: [],
            spotlightMetadata: [:],
            riskFlags: [],
            identity: FileIdentity(deviceIdentifier: nil, inodeIdentifier: nil, resourceIdentifier: nil),
            capabilities: [.canMove, .canTrash]
        )

        try await store.saveScanSession(session)
        try await store.saveFileRecords([record])
        let loaded = try await store.loadFileRecords(for: session.id)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, record.id)
    }

    func testActionExecutorMoveCanBeUndone() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("move-me.txt", isDirectory: false)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try Data("move".utf8).write(to: source)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == source.standardizedFileURL })
        let databaseURL = root.appendingPathComponent("test.sqlite", isDirectory: false)
        let store = try SQLiteStore(databaseURL: databaseURL)
        let memory = MemoryEngine(store: store)
        let executor = TestFixtures.makeExecutor(store: store)
        let undo = UndoManagerService(store: store, memory: memory)
        let action = PlannedAction(
            id: "move-action",
            planID: "plan",
            actionType: .move,
            targets: [record.id],
            destination: destination,
            status: .approved,
            risk: .low,
            confidence: 1,
            reason: "test move",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("move-me.txt", isDirectory: false).path))

        let undoRecord = try XCTUnwrap(summary.undoRecords.first)
        _ = try await undo.restore(undoRecord)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testActionExecutorArchiveMovesOriginalToTrashAndCanRestore() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("archive-me.txt", isDirectory: false)
        let destination = root.appendingPathComponent("Archive", isDirectory: true)
        try Data("archive".utf8).write(to: source)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == source.standardizedFileURL })
        let databaseURL = root.appendingPathComponent("archive.sqlite", isDirectory: false)
        let store = try SQLiteStore(databaseURL: databaseURL)
        let memory = MemoryEngine(store: store)
        let executor = TestFixtures.makeExecutor(store: store)
        let undo = UndoManagerService(store: store, memory: memory)
        let action = PlannedAction(
            id: "archive-action",
            planID: "plan",
            actionType: .archive,
            targets: [record.id],
            destination: destination,
            status: .approved,
            risk: .medium,
            confidence: 1,
            reason: "test archive",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let archiveRecord = try XCTUnwrap(summary.undoRecords.first { $0.inverseAction == .moveToTrash })
        let restoreRecord = try XCTUnwrap(summary.undoRecords.first { $0.inverseAction == .restore })
        let archiveURL = try XCTUnwrap(archiveRecord.restoreURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        _ = try await undo.restore(restoreRecord)
        _ = try await undo.restore(archiveRecord)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testApprovedHighRiskPackageCleanupExecutesAfterExplicitReview() async throws {
        // Wave 2D: a user-approved high-risk package cleanup is the explicit review;
        // audit no longer dead-ends needsManualReview actions approved by the user.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("should-not-run", isDirectory: false)
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("package.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        let candidate = PackageCleanupCandidate(
            id: "dangerous",
            title: "Dangerous cleanup",
            commandPath: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "touch '\(marker.path)'"],
            dryRunOutput: "would remove state",
            risk: .high,
            category: .packageManagerCleanup
        )
        let action = PlannedAction(
            id: "package-action",
            planID: "plan",
            actionType: .runPackageManagerCleanup,
            targets: [candidate.id],
            destination: nil,
            status: .approved,
            risk: .high,
            confidence: 0.8,
            reason: "test package",
            userDecision: .approved,
            executedAt: nil,
            findingID: nil
        )

        let summary = await executor.execute(actions: [action], filesByID: [:], packageCandidates: [candidate])
        XCTAssertEqual(summary.logs.count, 1, "Approved package cleanup should execute")
        XCTAssertEqual(summary.failures.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "Executed package cleanup should have run")
    }

    func testReportGeneratorWritesLocalPDF() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("report.sqlite", isDirectory: false))
        let session = ScanSession(scanType: .selectedFolders, rootURLs: [root], permissionsSnapshot: "test", status: .completed, totalFilesSeen: 0)
        let plan = Plan(
            id: "plan",
            scanSessionID: session.id,
            createdAt: Date(),
            status: .proposed,
            summary: "test",
            estimatedReclaimableBytes: 0,
            estimatedFilesAffected: 0,
            riskBreakdown: [:],
            actions: []
        )
        let snapshot = StorageSnapshot(
            id: "snapshot",
            createdAt: Date(),
            totalBytes: 0,
            bytesByCategory: [:],
            bytesByRootPath: [:],
            bytesByProject: [:],
            removedBytesThroughApp: 0
        )
        let outcome = ScanOutcome(
            session: session,
            files: [],
            fingerprints: [],
            contentSummaries: [],
            projects: [],
            edges: [],
            findings: [],
            recommendations: [],
            snapshot: snapshot,
            packageCandidates: []
        )
        let report = try await ReportGenerator(store: store).generateCleanupReport(outcome: outcome, plan: plan, destination: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: report.path)
        let size = (attributes[FileAttributeKey.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testContentExtractorCreatesLocalTextSummaryWithoutAIUpload() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = root.appendingPathComponent("note.txt", isDirectory: false)
        try Data("invoice for cleanup test".utf8).write(to: note)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let summaries = await ContentExtractor().summarize(files: records, privacyMode: .snippetsAI)

        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.privacyLevel, .snippetsAI)
        XCTAssertTrue(summary.detectedTopics.contains("finance"))
        XCTAssertTrue(summary.textPreview?.contains("invoice") == true)
    }

    func testInboxOrganizationSuggestsAliasPlan() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent(AppIdentity.inboxFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let file = inbox.appendingPathComponent("loose.pdf", isDirectory: false)
        try Data("pdf-ish".utf8).write(to: file)
        let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date()) ?? Date()
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let (_, recommendations) = await OrganizationPlanner().suggestOrganization(files: records, sessionID: "scan")

        XCTAssertTrue(recommendations.contains { $0.actionType == .createAlias })
    }

    // MARK: - MemoryEngine Tests

    func testMemoryEngineNeverRuleDowngradesConfidence() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("memory.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)

        let fileURL = root.appendingPathComponent("test-cache.bin", isDirectory: false)
        try Data(repeating: 1, count: 1024).write(to: fileURL)
        let record = FileRecord(scanSessionID: "scan", url: fileURL, sizeBytes: 1024)
        let filesByID = [record.id: record]

        // Create a "never" memory rule for this directory.
        let action = PlannedAction(
            id: "action", planID: "plan", actionType: .moveToTrash,
            targets: [record.id], destination: nil, status: .approved,
            risk: .medium, confidence: 0.9, reason: "test",
            userDecision: .neverDoThisHere, executedAt: nil, findingID: nil
        )
        try await memory.learn(from: action, filesByID: filesByID)

        // A recommendation targeting the same file should be downgraded.
        let recommendation = Recommendation(
            id: "rec", findingID: "finding", actionType: .moveToTrash,
            targetFileIDs: [record.id], confidence: 0.9, risk: .medium,
            reason: "test", expectedBytesReclaimed: 1024,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let adjusted = try await memory.applyMemory(to: [recommendation], filesByID: filesByID)
        XCTAssertEqual(adjusted.count, 1)
        XCTAssertEqual(adjusted.first?.confidence, 0.55)
        XCTAssertEqual(adjusted.first?.risk, .high)
        XCTAssertEqual(adjusted.first?.actionType, .inspectOnly)
    }

    func testMemoryEngineAlwaysRuleKeepsAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("memory.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)

        let fileURL = root.appendingPathComponent("test-file.txt", isDirectory: false)
        try Data("hello".utf8).write(to: fileURL)
        let record = FileRecord(scanSessionID: "scan", url: fileURL, sizeBytes: 5)
        let filesByID = [record.id: record]

        let action = PlannedAction(
            id: "action", planID: "plan", actionType: .tag,
            targets: [record.id], destination: nil, status: .approved,
            risk: .low, confidence: 0.8, reason: "test",
            userDecision: .alwaysDoThis, executedAt: nil, findingID: nil
        )
        try await memory.learn(from: action, filesByID: filesByID)

        // "always" rules boost confidence by 0.15 (capped at 1.0).
        let recommendation = Recommendation(
            id: "rec", findingID: "finding", actionType: .tag,
            targetFileIDs: [record.id], confidence: 0.8, risk: .low,
            reason: "test", expectedBytesReclaimed: 0,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let adjusted = try await memory.applyMemory(to: [recommendation], filesByID: filesByID)
        XCTAssertEqual(adjusted.count, 1)
        XCTAssertEqual(adjusted.first?.confidence ?? 0, 0.95, accuracy: 0.01)
    }

    // MARK: - RiskFlag Tests

    func testRiskFlagEnumCoversAllProtectionCases() {
        // Verify the enum has all expected cases.
        XCTAssertEqual(RiskFlag.allCases.count, 10)
        XCTAssertTrue(RiskFlag.allCases.contains(.reviewOnly))
        XCTAssertTrue(RiskFlag.allCases.contains(.sipProtectedSystemPath))
        XCTAssertTrue(RiskFlag.allCases.contains(.protectedDirectory))
        XCTAssertTrue(RiskFlag.allCases.contains(.protectedFile))
        XCTAssertTrue(RiskFlag.allCases.contains(.secretOrCertificate))
        XCTAssertTrue(RiskFlag.allCases.contains(.projectManifest))
        XCTAssertTrue(RiskFlag.allCases.contains(.sourceOrConfig))
        XCTAssertTrue(RiskFlag.allCases.contains(.cloudSyncedLocalPath))
        XCTAssertTrue(RiskFlag.allCases.contains(.codingAgentMemoryOrConfig))
        XCTAssertTrue(RiskFlag.allCases.contains(.insideTrash))
    }

    func testPathSafetyPolicyUsesTypedRiskFlags() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let envURL = root.appendingPathComponent(".env", isDirectory: false)
        try Data("SECRET=1".utf8).write(to: envURL)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let envRecord = try XCTUnwrap(records.first { $0.url == envURL.standardizedFileURL })

        XCTAssertTrue(envRecord.riskFlags.contains(.protectedFile))
        XCTAssertFalse(envRecord.riskFlags.contains(.protectedDirectory))
    }

    func makeTemporaryDirectory() throws -> URL {
        try TestFixtures.makeTemporaryDirectory()
    }

    // MARK: - UndoManagerService Tests

    func testUndoManagerServiceRestoreMoveAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("undo-move.txt", isDirectory: false)
        let destination = root.appendingPathComponent("Moved", isDirectory: true)
        try Data("undo test".utf8).write(to: source)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == source.standardizedFileURL })
        let databaseURL = root.appendingPathComponent("undo-test.sqlite", isDirectory: false)
        let store = try SQLiteStore(databaseURL: databaseURL)
        let memory = MemoryEngine(store: store)
        let executor = TestFixtures.makeExecutor(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        let action = PlannedAction(
            id: "move-action", planID: "plan", actionType: .move,
            targets: [record.id], destination: destination, status: .approved,
            risk: .low, confidence: 1, reason: "test",
            userDecision: .approved, executedAt: nil, findingID: nil
        )

        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))

        let undoRecord = try XCTUnwrap(summary.undoRecords.first)
        let restored = try await undoService.restore(undoRecord)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testUndoManagerServiceRejectsExpiredUndo() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("expired.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        let expiredUndo = UndoRecord(
            id: "expired", operationLogID: "log", inverseAction: .restore,
            restoreURL: root.appendingPathComponent("original.txt"),
            trashURL: root.appendingPathComponent("trashed.txt"),
            validUntil: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            status: .available
        )

        do {
            _ = try await undoService.restore(expiredUndo)
            XCTFail("Expected undo to be rejected for expired record")
        } catch {
            // Expected - undo should fail for expired records
        }
    }

    func testUndoManagerServiceRejectsUnavailableUndo() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("unavail.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        let restoredUndo = UndoRecord(
            id: "restored", operationLogID: "log", inverseAction: .restore,
            restoreURL: nil, trashURL: nil, validUntil: nil, status: .restored
        )

        do {
            _ = try await undoService.restore(restoredUndo)
            XCTFail("Expected undo to be rejected for already-restored record")
        } catch let error as UndoManagerServiceError {
            guard case .undoUnavailable = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    // MARK: - MemoryEngine Pattern Detection Tests

    func testMemoryEngineDetectPatternsCreatesRulesFromRejections() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("patterns.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)

        let fileURL = root.appendingPathComponent("target.txt", isDirectory: false)
        try Data("target".utf8).write(to: fileURL)
        let record = FileRecord(scanSessionID: "scan", url: fileURL, sizeBytes: 6)
        let filesByID = [record.id: record]

        // Create 3 rejection actions for the same file
        var actions: [PlannedAction] = []
        for i in 1...3 {
            actions.append(PlannedAction(
                id: "action-\(i)", planID: "plan", actionType: .moveToTrash,
                targets: [record.id], destination: nil, status: .rejected,
                risk: .medium, confidence: 0.8, reason: "test \(i)",
                userDecision: .neverDoThisHere, executedAt: nil, findingID: nil
            ))
        }

        try await memory.detectPatterns(from: actions, filesByID: filesByID)

        // Verify a rule was created
        let rules = try await store.loadMemoryRules()
        let rejectionRules = rules.filter { $0.source == "learned decision" }
        XCTAssertFalse(rejectionRules.isEmpty, "Expected at least one learned rule from rejections")
    }

    func testMemoryEngineRecordRegretCreatesRule() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("regret.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)

        try await memory.recordRegret(
            operationLogID: "log-123",
            restoredFileID: "file-456",
            reason: "Needed later"
        )

        let rules = try await store.loadMemoryRules()
        let regretRules = rules.filter { $0.source == "regret" }
        XCTAssertEqual(regretRules.count, 1)
        XCTAssertTrue(regretRules.first?.rule.contains("Needed later") ?? false)
    }

    // MARK: - ContentExtractor Video Tests

    func testContentExtractorCreatesVideoSummary() async throws {
        // A file with the .mp4 extension always yields a metadata summary:
        // readVideoPreview emits a "video" label plus a size label even when
        // the file has no real video track (duration/track probes are optional).
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appendingPathComponent("test-video.mp4", isDirectory: false)
        try Data(repeating: 0, count: 1024).write(to: videoURL)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        // snippetsAI permits local metadata extraction (localOnly would correctly return no summaries).
        let summaries = await ContentExtractor().summarize(files: records, privacyMode: .snippetsAI)

        let summary = try XCTUnwrap(summaries.first, "A .mp4 file should produce a video metadata summary")
        XCTAssertFalse(summary.videoLabels.isEmpty, "Expected video labels in summary")
        XCTAssertTrue(summary.videoLabels.contains("video"))
        XCTAssertTrue(summary.videoLabels.contains(where: { $0.hasPrefix("size:") }))
    }

    // MARK: - SpaceForecaster Tests

    func testSpaceForecasterReturnsNilWithInsufficientData() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("forecast.sqlite", isDirectory: false))
        let forecaster = SpaceForecaster(store: store)

        // With no snapshots, should return nil
        let forecast = try await forecaster.forecast(diskCapacity: 500_000_000_000)
        XCTAssertNil(forecast)
    }

    func testSpaceForecasterCalculatesGrowthRate() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("forecast2.sqlite", isDirectory: false))
        let forecaster = SpaceForecaster(store: store)

        // Create two snapshots with growth
        let snapshot1 = StorageSnapshot(
            id: "s1", createdAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            totalBytes: 100_000_000, bytesByCategory: [:], bytesByRootPath: [:],
            bytesByProject: [:], removedBytesThroughApp: 0
        )
        let snapshot2 = StorageSnapshot(
            id: "s2", createdAt: Date(),
            totalBytes: 200_000_000, bytesByCategory: [:], bytesByRootPath: [:],
            bytesByProject: [:], removedBytesThroughApp: 0
        )
        try await store.saveStorageSnapshot(snapshot1)
        try await store.saveStorageSnapshot(snapshot2)

        // Keep this fixture independent of the host disk's actual free space.
        let forecast = try await forecaster.forecast(capacity: 500_000_000_000, availableBytes: 200_000_000_000)
        XCTAssertNotNil(forecast)
        XCTAssertGreaterThan(forecast?.dailyGrowthRate ?? 0, 0)
    }

    // MARK: - ActionExecutor Rename Tests

    func testActionExecutorRenameCanBeUndone() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("old-name.txt", isDirectory: false)
        let destination = root.appendingPathComponent("Renamed", isDirectory: true)
        // The rename executor moves the file into `destination` but does not create
        // the directory itself (unlike .move); the test must provide it.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("rename test".utf8).write(to: source)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = try XCTUnwrap(records.first { $0.url == source.standardizedFileURL })
        let databaseURL = root.appendingPathComponent("rename.sqlite", isDirectory: false)
        let store = try SQLiteStore(databaseURL: databaseURL)
        let memory = MemoryEngine(store: store)
        let executor = TestFixtures.makeExecutor(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        // Create a record with identity fields set (as the crawler would)
        var recordWithIdentity = record
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        recordWithIdentity.identity = FileIdentity(
            deviceIdentifier: (attrs[.systemNumber] as? NSNumber)?.uint64Value,
            inodeIdentifier: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
            resourceIdentifier: nil
        )

        let action = PlannedAction(
            id: "rename-action", planID: "plan", actionType: .rename,
            targets: [recordWithIdentity.id], destination: destination, status: .approved,
            risk: .low, confidence: 1, reason: "test rename",
            userDecision: .approved, executedAt: nil, findingID: nil
        )

        let summary = await executor.execute(actions: [action], filesByID: [recordWithIdentity.id: recordWithIdentity])

        // With identity fields set (as the crawler produces them), SafetyAuditor
        // verifies the file and allows the low-risk rename — the outcome is
        // deterministic: the file moves, an undo record exists, and undo restores it.
        XCTAssertTrue(summary.failures.isEmpty, "Rename should succeed when identity is verified: \(summary.failures)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("old-name.txt").path))

        let undoRecord = try XCTUnwrap(summary.undoRecords.first)
        let restored = try await undoService.restore(undoRecord)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - SQLiteStore Database URL Test

    func testSQLiteStoreProvidesDatabaseURL() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("url-test.sqlite", isDirectory: false)
        let store = try SQLiteStore(databaseURL: databaseURL)

        let url = await store.databaseFileURL()
        XCTAssertEqual(url.path, databaseURL.path)
    }

    // MARK: - SortedPathSearch Tests

    func testSortedPathSearchHandlesUnicodePaths() {
        let paths = ["/a/α.txt", "/a/β.txt", "/a/γ.txt", "/b/file.txt"]
        let lower = SortedPathSearch.lowerBound(paths, "/a/")
        let upper = SortedPathSearch.upperBound(paths, "/a/")
        XCTAssertEqual(lower, 0)
        XCTAssertEqual(upper, 3)
    }

    // MARK: - ProcessRunner Tests

    func testProcessRunnerHandlesTimeout() async {
        let result = await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            timeout: 0.1
        )
        XCTAssertEqual(result.exitCode, 124)
        XCTAssertTrue(result.stderr.contains("timed out"))
    }

    func testProcessRunnerHandlesInvalidCommand() async {
        let result = await ProcessRunner.run(
            URL(fileURLWithPath: "/nonexistent/command"),
            arguments: [],
            timeout: 5
        )
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.stderr.isEmpty)
    }

    // MARK: - CleanerRuleEngine Individual Rules

    func testCleanerRuleEngineDetectsScreenshotFindings() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let screenshot1 = root.appendingPathComponent("Screen Shot 2024-01-01 at 10.00.00.png", isDirectory: false)
        let screenshot2 = root.appendingPathComponent("Screenshot 2024-01-02 at 11.00.00.png", isDirectory: false)
        try Data(repeating: 0, count: 1024).write(to: screenshot1)
        try Data(repeating: 0, count: 2048).write(to: screenshot2)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [], sessionID: "scan")

        let screenshotFindings = findings.filter { $0.category == .screenshot && $0.evidence["type"] == "screenshot" }
        XCTAssertEqual(screenshotFindings.count, 1)
        XCTAssertEqual(screenshotFindings.first?.targetFileIDs.count, 2)
    }

    func testCleanerRuleEngineDetectsLargeFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Sparse file: 1.1 GB logical size with ~0 real disk blocks (APFS).
        let largeFile = root.appendingPathComponent("large-video.mp4", isDirectory: false)
        try TestFileFixtures.makeSparseFile(at: largeFile, logicalSize: 1_100_000_000)
        // Small file that must NOT be flagged as large.
        let smallFile = root.appendingPathComponent("small.txt", isDirectory: false)
        try Data(repeating: 1, count: 1024).write(to: smallFile)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let largeRecord = try XCTUnwrap(records.first { $0.fileName == "large-video.mp4" })
        XCTAssertGreaterThanOrEqual(largeRecord.sizeBytes, 1_000_000_000,
                                     "Sparse file should report its logical size")

        let engine = CleanerRuleEngine()
        let (findings, recommendations) = await engine.analyze(files: records, projects: [], sessionID: "scan")

        let largeFindings = findings.filter { $0.category == .largeFile }
        XCTAssertEqual(largeFindings.count, 1, "The single >= 1 GB file should be flagged as large")
        XCTAssertEqual(largeFindings.first?.targetFileIDs, [largeRecord.id])
        XCTAssertTrue(recommendations.contains { $0.targetFileIDs.contains(largeRecord.id) && $0.actionType == .inspectOnly },
                      "Large files should recommend inspect-only review")
        let smallRecord = try XCTUnwrap(records.first { $0.fileName == "small.txt" })
        XCTAssertFalse(largeFindings.contains { $0.targetFileIDs.contains(smallRecord.id) },
                       "A small file should never be flagged as large")
    }

    func testCleanerRuleEngineDetectsCacheFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheDir = root.appendingPathComponent("Library/Caches/TestApp", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2 * 1024 * 1024).write(to: cacheDir.appendingPathComponent("cache.bin", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [], sessionID: "scan")

        let cacheFindings = findings.filter { $0.category == .cache }
        XCTAssertFalse(cacheFindings.isEmpty)
    }

    // MARK: - End-to-End Scan → Plan → Execute → Undo Flow

    func testEndToEndScanPlanExecuteUndoFlow() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Create test files
        let file1 = root.appendingPathComponent("file1.txt", isDirectory: false)
        let file2 = root.appendingPathComponent("file2.log", isDirectory: false)
        try Data("content1".utf8).write(to: file1)
        try Data(repeating: 1, count: 2 * 1024 * 1024).write(to: file2) // > 1MB log file

        // Set up store and services
        let databaseURL = root.appendingPathComponent("e2e.sqlite", isDirectory: false)
        let store = try SQLiteStore(databaseURL: databaseURL)
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)
        let executor = TestFixtures.makeExecutor(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        // 1. Scan
        let (outcome, plan) = try await orchestrator.scan(
            mode: .selectedFolders,
            selectedFolders: [root],
            providerSettings: ProviderSettings(),
            includeAI: false
        )
        XCTAssertFalse(plan.actions.isEmpty, "Plan should have actions")

        // 2. Plan already has actions from scan

        // 3. Approve some actions
        var approvedPlan = plan
        for i in approvedPlan.actions.indices {
            if approvedPlan.actions[i].risk == .low {
                approvedPlan.actions[i].userDecision = .approved
                approvedPlan.actions[i].status = .approved
            }
        }

        // 4. Execute approved actions
        let summary = await executor.execute(
            actions: approvedPlan.actions,
            filesByID: outcome.files.reduce(into: [:]) { $0[$1.id] = $1 }
        )
        XCTAssertFalse(summary.undoRecords.isEmpty, "Should have undo records")

        // 5. Undo one action
        if let undoRecord = summary.undoRecords.first, undoRecord.inverseAction == .restore {
            let restored = try await undoService.restore(undoRecord)
            XCTAssertEqual(restored.status, .restored)
        }
    }

    // MARK: - FileCrawler Edge Cases

    func testFileCrawlerHandlesSymlinks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realFile = root.appendingPathComponent("real.txt", isDirectory: false)
        let symlink = root.appendingPathComponent("link.txt", isDirectory: false)
        try Data("content".utf8).write(to: realFile)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")

        let realRecord = records.first { $0.fileName == "real.txt" }
        let symlinkRecord = records.first { $0.fileName == "link.txt" }

        XCTAssertNotNil(realRecord)
        XCTAssertNotNil(symlinkRecord)
        XCTAssertTrue(symlinkRecord?.isSymlink ?? false)
    }

    func testFileCrawlerHandlesPermissionErrors() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let restrictedDir = root.appendingPathComponent("Restricted", isDirectory: true)
        try FileManager.default.createDirectory(at: restrictedDir, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: restrictedDir.appendingPathComponent("secret.txt", isDirectory: false))

        // Remove read permissions so the enumerator cannot open the root.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restrictedDir.path)
        // Restore permissions before the temp dir is removed so cleanup always works.
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restrictedDir.path) }

        let crawler = FileCrawler()
        let (records, errors) = await crawler.crawl(rootURLs: [restrictedDir], sessionID: "scan")

        if errors == 0 && !records.isEmpty {
            // chmod 000 is not enforced for this process (e.g. root or Full Disk
            // Access), so the permission-denied path cannot be reproduced here.
            throw XCTSkip("chmod 000 is not enforced for this test process")
        }
        // Crawling an unreadable root must report the failure instead of crashing.
        XCTAssertGreaterThan(errors, 0, "Unreadable scan root should be reported as an error")
        XCTAssertTrue(records.isEmpty, "No records should be produced from an unreadable root")
    }

    // MARK: - NL Command Tests

    func testPlannerAgentNaturalLanguageDownloadsCommand() async {
        let planner = PlannerAgent()
        let downloadRecord = makeFileRecord(id: "d1", path: "/Users/me/Downloads/file.zip", sizeBytes: 1000)
        let otherRecord = makeFileRecord(id: "o1", path: "/Users/me/Documents/file.txt", sizeBytes: 500)
        let filesByID = [downloadRecord.id: downloadRecord, otherRecord.id: otherRecord]
        let rec1 = makeRecommendation(id: "r1", targetID: "d1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "o1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)
        XCTAssertEqual(plan.actions.count, 2)

        let filtered = await planner.planForNaturalLanguageCommand("clean downloads", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1)
        XCTAssertEqual(filtered.actions.first?.targets.first, "d1")
    }

    func testPlannerAgentNaturalLanguageCachesCommand() async {
        let planner = PlannerAgent()
        let cacheRecord = makeFileRecord(id: "c1", path: "/Users/me/Library/Caches/com.app/data", sizeBytes: 5000)
        let otherRecord = makeFileRecord(id: "o1", path: "/Users/me/Documents/file.txt", sizeBytes: 500)
        let filesByID = [cacheRecord.id: cacheRecord, otherRecord.id: otherRecord]
        let rec1 = makeRecommendation(id: "r1", targetID: "c1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "o1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("clear caches", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1)
        XCTAssertEqual(filtered.actions.first?.targets.first, "c1")
    }

    func testPlannerAgentNaturalLanguageDockerCommand() async {
        let planner = PlannerAgent()
        let dockerRecord = makeFileRecord(id: "d1", path: "/Users/me/Docker/data", sizeBytes: 5000)
        let otherRecord = makeFileRecord(id: "o1", path: "/Users/me/Documents/file.txt", sizeBytes: 500)
        let filesByID = [dockerRecord.id: dockerRecord, otherRecord.id: otherRecord]
        let rec1 = makeRecommendation(id: "r1", targetID: "d1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "o1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("clean docker", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1)
        XCTAssertEqual(filtered.actions.first?.targets.first, "d1")
    }

    func testPlannerAgentNaturalLanguageNpmCommand() async {
        let planner = PlannerAgent()
        let npmRecord = makeFileRecord(id: "n1", path: "/Users/me/project/node_modules/pkg/index.js", sizeBytes: 5000)
        let otherRecord = makeFileRecord(id: "o1", path: "/Users/me/Documents/file.txt", sizeBytes: 500)
        let filesByID = [npmRecord.id: npmRecord, otherRecord.id: otherRecord]
        let rec1 = makeRecommendation(id: "r1", targetID: "n1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "o1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("clean npm", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1)
        XCTAssertEqual(filtered.actions.first?.targets.first, "n1")
    }

    func testPlannerAgentNaturalLanguageOrganizeCommand() async {
        let planner = PlannerAgent()
        let record = makeFileRecord(id: "f1", path: "/Users/me/Downloads/file.txt", sizeBytes: 500)
        let filesByID = [record.id: record]
        let rec = makeRecommendation(id: "r1", targetID: "f1", action: .tag, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec], filesByID: filesByID)
        XCTAssertEqual(plan.actions.first?.actionType, .tag)

        let filtered = await planner.planForNaturalLanguageCommand("organize files", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.first?.actionType, .move)
    }

    func testPlannerAgentNaturalLanguageEverythingRestoresOriginal() async {
        let planner = PlannerAgent()
        let r1 = makeFileRecord(id: "f1", path: "/Users/me/a.txt", sizeBytes: 500)
        let r2 = makeFileRecord(id: "f2", path: "/Users/me/b.txt", sizeBytes: 500)
        let filesByID = [r1.id: r1, r2.id: r2]
        let rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "f2", action: .moveToTrash, risk: .high)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)
        XCTAssertEqual(plan.actions.count, 2)

        // Filter to safe only
        let filtered = await planner.planForNaturalLanguageCommand("be safe", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1)

        // Restore everything
        let restored = await planner.planForNaturalLanguageCommand("show everything", existingPlan: filtered, filesByID: filesByID)
        XCTAssertEqual(restored.actions.count, 2)
    }

    // MARK: - CleanerRuleEngine Tests

    func testRuleEngineDetectsOldDownloads() async throws {
        // Controlled fixture: a temp "Downloads" folder with an installer whose
        // modification date is 60 days old. The real ~/Downloads is never touched.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloadsDir = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let testFile = downloadsDir.appendingPathComponent("old-installer-\(UUID().uuidString).dmg", isDirectory: false)
        try Data(repeating: 0, count: 2000).write(to: testFile)
        let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: testFile.path)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let testRecord = try XCTUnwrap(records.first { $0.url == testFile.standardizedFileURL })
        XCTAssertNotNil(testRecord.modifiedAt, "Modified date should be set")
        XCTAssertTrue(testRecord.url.pathComponents.contains("Downloads"), "Path should contain Downloads")

        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [], sessionID: "scan")
        let testFindings = findings.filter { $0.targetFileIDs.contains(testRecord.id) }
        XCTAssertFalse(testFindings.isEmpty, "Old installer in Downloads should be detected")
        XCTAssertTrue(testFindings.contains { $0.category == .oldInstaller || $0.category == .oldDownload },
                      "Old installers should map to the old-download finding category")
    }

    func testRuleEngineGroupsScreenshotsByFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2000).write(to: desktop.appendingPathComponent("Screenshot 2024-01-01.png", isDirectory: false))
        try Data(repeating: 0, count: 2000).write(to: desktop.appendingPathComponent("Screenshot 2024-01-02.png", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [], sessionID: "scan")
        let screenshotFindings = findings.filter { $0.category == .screenshot }
        XCTAssertFalse(screenshotFindings.isEmpty, "Screenshots should be detected")
        // Each screenshot finding should target specific files, not all screenshots lumped together
        for finding in screenshotFindings {
            XCTAssertFalse(finding.targetFileIDs.isEmpty, "Screenshot finding should have target files")
        }
    }
    // MARK: - PathSafetyPolicy Tests

    func testPathSafetyPolicyShouldSkipTraversalProtectedDirs() {
        let policy = PathSafetyPolicy()
        let sshDir = URL(fileURLWithPath: "/Users/me/.ssh/config")
        XCTAssertTrue(policy.shouldSkipTraversal(of: sshDir), ".ssh should be skipped")

        let nodeModules = URL(fileURLWithPath: "/Users/me/project/node_modules/pkg")
        XCTAssertFalse(policy.shouldSkipTraversal(of: nodeModules), "node_modules should NOT be skipped")

        let protectedInNodeModules = URL(fileURLWithPath: "/Users/me/.config/node_modules/pkg")
        XCTAssertTrue(policy.shouldSkipTraversal(of: protectedInNodeModules), ".config inside path should be skipped even with node_modules")
    }

    func testPathSafetyPolicyCloudProviderDetection() {
        let policy = PathSafetyPolicy()
        XCTAssertEqual(policy.cloudProvider(for: URL(fileURLWithPath: "/Users/me/Mobile Documents/file.txt")), "iCloud")
        XCTAssertEqual(policy.cloudProvider(for: URL(fileURLWithPath: "/Users/me/iCloud Drive/file.txt")), "iCloud")
        XCTAssertEqual(policy.cloudProvider(for: URL(fileURLWithPath: "/Users/me/Dropbox/file.txt")), "Dropbox")
        XCTAssertEqual(policy.cloudProvider(for: URL(fileURLWithPath: "/Users/me/Google Drive/file.txt")), "Google Drive")
        XCTAssertEqual(policy.cloudProvider(for: URL(fileURLWithPath: "/Users/me/OneDrive/file.txt")), "OneDrive")
        XCTAssertNil(policy.cloudProvider(for: URL(fileURLWithPath: "/Users/me/Documents/file.txt")))
    }

    func testPathSafetyPolicySIPPathsAreShared() {
        let policy = PathSafetyPolicy()
        // Both riskFlags and shouldSkipTraversal should agree on SIP paths
        let sipURL = URL(fileURLWithPath: "/usr/bin/ls")
        let flags = policy.riskFlags(for: sipURL, isDirectory: false)
        XCTAssertTrue(flags.contains(.sipProtectedSystemPath), "SIP path should have risk flag")
        XCTAssertTrue(policy.shouldSkipTraversal(of: sipURL), "SIP path should be skipped")
    }

    // MARK: - MemoryEngine Tests

    func testMemoryEngineDirectoryScopeMatching() async throws {
        // A "never" rule learned for one directory must apply to files inside
        // it (with a "/" boundary) but must never leak to similarly-named
        // sibling directories like "test-dir-other".
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("scope.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)

        let targetDir = root.appendingPathComponent("test-dir", isDirectory: true)
        let siblingDir = root.appendingPathComponent("test-dir-other", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingDir, withIntermediateDirectories: true)
        let insideFile = targetDir.appendingPathComponent("inside.txt", isDirectory: false)
        let outsideFile = siblingDir.appendingPathComponent("outside.txt", isDirectory: false)
        try Data("inside".utf8).write(to: insideFile)
        try Data("outside".utf8).write(to: outsideFile)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let insideRecord = try XCTUnwrap(records.first { $0.url == insideFile.standardizedFileURL })
        let outsideRecord = try XCTUnwrap(records.first { $0.url == outsideFile.standardizedFileURL })
        let filesByID = [insideRecord.id: insideRecord, outsideRecord.id: outsideRecord]

        // Learn a "never" rule scoped to targetDir via the user-decision API.
        let action = PlannedAction(
            id: "action", planID: "plan", actionType: .moveToTrash,
            targets: [insideRecord.id], destination: nil, status: .approved,
            risk: .low, confidence: 0.9, reason: "test",
            userDecision: .neverDoThisHere, executedAt: nil, findingID: nil
        )
        try await memory.learn(from: action, filesByID: filesByID)

        func makeRecommendation(targetID: String) -> Recommendation {
            Recommendation(
                id: "rec-\(targetID)", findingID: "finding-\(targetID)",
                actionType: .moveToTrash, targetFileIDs: [targetID],
                confidence: 0.9, risk: .low, reason: "test",
                expectedBytesReclaimed: 10, requiresConfirmation: true,
                llmTraceID: nil, policyTraceID: nil
            )
        }

        let adjusted = try await memory.applyMemory(
            to: [makeRecommendation(targetID: insideRecord.id),
                 makeRecommendation(targetID: outsideRecord.id)],
            filesByID: filesByID
        )
        let insideAdjusted = try XCTUnwrap(adjusted.first { $0.targetFileIDs == [insideRecord.id] })
        let outsideAdjusted = try XCTUnwrap(adjusted.first { $0.targetFileIDs == [outsideRecord.id] })

        // Inside the scope: downgraded to inspectOnly at 0.55 confidence.
        XCTAssertEqual(insideAdjusted.confidence, 0.55, "File inside the rule scope should be downgraded")
        XCTAssertEqual(insideAdjusted.actionType, .inspectOnly)
        // Outside the scope ("test-dir-other" must not match the "test-dir/"
        // prefix): the recommendation must pass through untouched.
        XCTAssertEqual(outsideAdjusted.confidence, 0.9, "File outside the rule scope should be untouched")
        XCTAssertEqual(outsideAdjusted.actionType, .moveToTrash)
    }

    func testMemoryEngineNeverRuleConfidenceDowngrade() async throws {
        // A global "never" calibration rule must downgrade confidence, escalate
        // risk, convert moveToTrash to inspectOnly, and annotate the reason —
        // verified through the real MemoryEngine.applyMemory pipeline.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("never-rule.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)
        try await memory.applyCalibrationPreference(
            "Never suggest moveToTrash in this directory",
            scopeType: "global", scopeValue: ""
        )

        let file = makeFileRecord(id: "f1", path: "/tmp/test.txt", sizeBytes: 100)
        let rec = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        let adjusted = try await memory.applyMemory(to: [rec], filesByID: [file.id: file])
        let result = try XCTUnwrap(adjusted.first)
        XCTAssertEqual(result.confidence, 0.55, "Never rule should cap confidence at 0.55")
        XCTAssertEqual(result.risk, .high, "Never rule should escalate risk to high")
        XCTAssertEqual(result.actionType, .inspectOnly, "Never rule should convert moveToTrash to inspectOnly")
        XCTAssertTrue(result.reason.contains("Memory rule applied"), "Never rule should annotate the reason")
    }

    // MARK: - Helpers

    func makeFileRecord(id: String, path: String, sizeBytes: Int64) -> FileRecord {
        TestFixtures.makeFileRecord(id: id, path: path, sizeBytes: sizeBytes)
    }

    func makeRecommendation(id: String, targetID: String, action: ActionType, risk: RiskLevel, confidence: Double = 0.8) -> Recommendation {
        TestFixtures.makeRecommendation(id: id, targetID: targetID, action: action, risk: risk, confidence: confidence)
    }

    // MARK: - Comprehensive Service Tests

    // --- CleanerRuleEngine: Developer Artifacts (SP-16) ---

    func testRuleEngineDetectsNodeModules() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // package.json makes "project" a detected project root so node_modules
        // inside it is a valid project-bound build output.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("project", isDirectory: true), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("project/package.json", isDirectory: false))
        let nmDir = root.appendingPathComponent("project/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nmDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 5000).write(to: nmDir.appendingPathComponent("index.js", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        // node_modules is a project-bound build output: it only matches inside a
        // detected project root (a directory with a manifest such as package.json).
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        let project = ProjectUnit(
            id: "p1", name: "project", rootURL: projectRoot, projectType: "Node",
            confidence: 0.95, lastActivityAt: nil,
            manifestFiles: [projectRoot.appendingPathComponent("package.json")],
            sourceFilesCount: 0, generatedFilesCount: 0, totalBytes: 5000,
            reclaimableBytes: 5000, status: .active
        )
        let (findings, recs) = await engine.analyze(files: records, projects: [project], sessionID: "scan")
        let devFindings = findings.filter { $0.category == .developerArtifact }
        XCTAssertFalse(devFindings.isEmpty, "node_modules should be detected as developer artifact")
        XCTAssertFalse(recs.isEmpty, "Should generate recommendations for node_modules")
    }

    func testRuleEngineDetectsPycache() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheDir = root.appendingPathComponent("project/__pycache__", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1000).write(to: cacheDir.appendingPathComponent("module.pyc", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [], sessionID: "scan")
        let devFindings = findings.filter { $0.category == .developerArtifact }
        XCTAssertFalse(devFindings.isEmpty, "__pycache__ should be detected as developer artifact")
    }

    func testRuleEngineDetectsDerivedData() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ddDir = root.appendingPathComponent("DerivedData/Project-abc", isDirectory: true)
        try FileManager.default.createDirectory(at: ddDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 5000).write(to: ddDir.appendingPathComponent("build.o", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [], sessionID: "scan")
        let devFindings = findings.filter { $0.category == .developerArtifact }
        XCTAssertFalse(devFindings.isEmpty, "DerivedData should be detected as developer artifact")
    }

    // --- CleanerRuleEngine: Coding Agent Artifacts (SP-20) ---

    func testRuleEngineDetectsCodingAgentLogs() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let agentDir = root.appendingPathComponent("project/.claude/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2000).write(to: agentDir.appendingPathComponent("session.log", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let engine = CleanerRuleEngine()
        let (findings, _) = await engine.analyze(files: records, projects: [], sessionID: "scan")
        let agentFindings = findings.filter { $0.category == .codingAgentArtifact }
        XCTAssertFalse(agentFindings.isEmpty, "Coding agent logs should be detected")
    }

    // --- CleanerRuleEngine: Large Files (SP-22) ---
    // Positive and negative large-file cases are covered by
    // testCleanerRuleEngineDetectsLargeFiles above (sparse 1.1 GB fixture).

    // --- DuplicateDetector: Exact Duplicates (SP-08) ---

    func testDuplicateDetectorFindsExactDuplicates() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "This is duplicate content for testing purposes."
        try Data(content.utf8).write(to: root.appendingPathComponent("copy1.txt", isDirectory: false))
        try Data(content.utf8).write(to: root.appendingPathComponent("copy2.txt", isDirectory: false))
        try Data("unique content".utf8).write(to: root.appendingPathComponent("unique.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(files: records, sessionID: "scan")
        XCTAssertFalse(analysis.findings.isEmpty, "Exact duplicates should be detected")
        XCTAssertFalse(analysis.edges.isEmpty, "Duplicate edges should be created")
    }

    func testDuplicateDetectorIgnoresDifferentFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("content A".utf8).write(to: root.appendingPathComponent("a.txt", isDirectory: false))
        try Data("content B".utf8).write(to: root.appendingPathComponent("b.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(files: records, sessionID: "scan")
        XCTAssertTrue(analysis.findings.isEmpty, "Different files should not be flagged as duplicates")
    }

    // --- ProjectDetector (SP-07) ---

    func testProjectDetectorFindsPackageJSON() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pkg = root.appendingPathComponent("package.json", isDirectory: false)
        try Data("{}".utf8).write(to: pkg)
        try Data("console.log('hi')".utf8).write(to: root.appendingPathComponent("index.js", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = ProjectDetector()
        let projects = await detector.detectProjects(in: records)
        XCTAssertFalse(projects.isEmpty, "Project with package.json should be detected")
        XCTAssertEqual(projects.first?.projectType, "Node")
    }

    func testProjectDetectorFindsCargoToml() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("[package]".utf8).write(to: root.appendingPathComponent("Cargo.toml", isDirectory: false))
        let srcDir = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try Data("fn main() {}".utf8).write(to: srcDir.appendingPathComponent("main.rs", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = ProjectDetector()
        let projects = await detector.detectProjects(in: records)
        XCTAssertFalse(projects.isEmpty, "Rust project should be detected")
        XCTAssertEqual(projects.first?.projectType, "Rust")
    }

    // --- OrganizationPlanner (SP-25) ---

    func testOrganizationPlannerSuggestsForOldDownloads() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let file = downloads.appendingPathComponent("report.pdf", isDirectory: false)
        try Data(repeating: 0, count: 1000).write(to: file)
        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let planner = OrganizationPlanner()
        let (findings, recs) = await planner.suggestOrganization(files: records, sessionID: "scan")
        // Files 7-29 days old in Downloads should get organization suggestions
        XCTAssertFalse(findings.isEmpty, "Old files in Downloads should get organization suggestions")
        XCTAssertFalse(recs.isEmpty, "Should generate organization recommendations")
    }

    // --- PlannerAgent: Plan Generation (PR-13, PR-14, PR-15) ---

    func testPlannerAgentSortsByRiskThenConfidence() async {
        let planner = PlannerAgent()
        let rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        let rec2 = makeRecommendation(id: "r2", targetID: "f2", action: .moveToTrash, risk: .high, confidence: 0.8)
        let rec3 = makeRecommendation(id: "r3", targetID: "f3", action: .moveToTrash, risk: .low, confidence: 0.7)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2, rec3], filesByID: [:])
        // PlannerAgent sorts ascending by risk, then descending by confidence:
        // low(0.9) -> low(0.7) -> high(0.8).
        XCTAssertEqual(plan.actions.map(\.targets), [["f1"], ["f3"], ["f2"]],
                       "Actions should sort by risk ascending, then confidence descending")
        XCTAssertEqual(plan.actions.map(\.risk), [.low, .low, .high])
        XCTAssertEqual(plan.actions.map(\.confidence), [0.9, 0.7, 0.8])
    }

    func testPlannerAgentGeneratesSummary() async {
        let planner = PlannerAgent()
        let rec = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec], filesByID: [:])
        XCTAssertFalse(plan.summary.isEmpty, "Plan should have a summary")
        // Summary format: "<count> proposed actions: <low> low risk, ..."
        XCTAssertTrue(plan.summary.contains("1 proposed actions"), "Summary should count the single action: \(plan.summary)")
        XCTAssertTrue(plan.summary.contains("1 low risk"), "Summary should report the low-risk count: \(plan.summary)")
    }

    // --- MemoryEngine: Calibration (ML-05) ---

    func testMemoryEngineAppliesCalibration() async throws {
        // Use a unique database URL to avoid pollution from other tests
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("cal-test.sqlite"))
        let memory = MemoryEngine(store: store)
        try await memory.applyCalibrationPreference("Prefer archive over delete for all files")
        let rules = try await store.loadMemoryRules()
        XCTAssertEqual(rules.count, 1, "Should have exactly 1 calibration rule")
        XCTAssertTrue(rules.first?.rule.contains("archive") ?? false)
    }

    // --- PathSafetyPolicy: Protected Paths (PS-04, PS-05, PS-06, PS-07, PS-08) ---

    func testPathSafetyPolicyProtectsSSH() {
        let policy = PathSafetyPolicy()
        let sshFile = URL(fileURLWithPath: "/Users/me/.ssh/id_rsa")
        XCTAssertTrue(policy.isProtectedFromCleanup(url: sshFile, isDirectory: false))
    }

    func testPathSafetyPolicyProtectsEnvFiles() {
        let policy = PathSafetyPolicy()
        let envFile = URL(fileURLWithPath: "/Users/me/project/.env")
        XCTAssertTrue(policy.isProtectedFromCleanup(url: envFile, isDirectory: false))
    }

    func testPathSafetyPolicyProtectsCertificates() {
        let policy = PathSafetyPolicy()
        let certFile = URL(fileURLWithPath: "/Users/me/cert.pem")
        XCTAssertTrue(policy.isProtectedFromCleanup(url: certFile, isDirectory: false))
    }

    func testPathSafetyPolicyProtectsSourceCode() {
        let policy = PathSafetyPolicy()
        let swiftFile = URL(fileURLWithPath: "/Users/me/project/main.swift")
        let flags = policy.riskFlags(for: swiftFile, isDirectory: false)
        XCTAssertTrue(flags.contains(.sourceOrConfig))
    }

    func testPathSafetyPolicyProtectsManifests() {
        let policy = PathSafetyPolicy()
        let pkgFile = URL(fileURLWithPath: "/Users/me/project/package.json")
        let flags = policy.riskFlags(for: pkgFile, isDirectory: false)
        XCTAssertTrue(flags.contains(.projectManifest))
    }

    func testPathSafetyPolicyProtectsCodingAgentConfigs() {
        let policy = PathSafetyPolicy()
        let claudeFile = URL(fileURLWithPath: "/Users/me/project/.claude/settings.json")
        XCTAssertTrue(policy.isProtectedFromCleanup(url: claudeFile, isDirectory: false))
    }

    // --- FileCrawler: Metadata Extraction (SP-01) ---

    func testFileCrawlerExtractsFileSize() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.txt", isDirectory: false)
        try Data(repeating: 0, count: 42).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.sizeBytes, 42)
    }

    func testFileCrawlerExtractsFileName() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.pdf", isDirectory: false)
        try Data(repeating: 0, count: 10).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.fileName, "document.pdf")
        XCTAssertEqual(record?.fileExtension, "pdf")
    }

    func testFileCrawlerDetectsDirectories() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let subdir = root.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let dirRecord = records.first { $0.url == subdir.standardizedFileURL }
        XCTAssertNotNil(dirRecord)
        XCTAssertEqual(dirRecord?.kind, .directory)
    }

    // --- SQLiteStore: Persistence (DP-01, DP-02, DP-04) ---

    func testSQLiteStorePersistsAndLoadsPlans() async throws {
        let store = try SQLiteStore.inMemory()
        let plan = Plan(
            id: "plan-1", scanSessionID: "scan-1", createdAt: Date(), status: .proposed,
            summary: "Test plan", estimatedReclaimableBytes: 1000, estimatedFilesAffected: 5,
            riskBreakdown: [.low: 3, .medium: 2], actions: []
        )
        try await store.savePlan(plan)
        let loaded = try await store.loadPlan(id: "plan-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "plan-1")
        XCTAssertEqual(loaded?.summary, "Test plan")
    }

    func testSQLiteStorePersistsAndLoadsMemoryRules() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("rule-test.sqlite"))
        let rule = MemoryRule(
            id: "rule-test-\(UUID().uuidString)", scopeType: "global", scopeValue: "",
            rule: "Test rule", source: "test", confidence: 0.9,
            createdAt: Date(), lastReinforcedAt: nil, ruleType: .never
        )
        try await store.saveMemoryRule(rule)
        let rules = try await store.loadMemoryRules()
        XCTAssertGreaterThanOrEqual(rules.count, 1)
        let loaded = rules.first { $0.id == rule.id }
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.ruleType, .never)
    }

    func testSQLiteStorePersistsAndLoadsUndoRecords() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("undo-test.sqlite"))
        let undoID = "undo-test-\(UUID().uuidString)"
        let undo = UndoRecord(
            id: undoID, operationLogID: "log-1", inverseAction: .restore,
            restoreURL: URL(fileURLWithPath: "/tmp/file.txt"), trashURL: nil,
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            status: .available
        )
        try await store.saveUndoRecord(undo)
        let records = try await store.loadUndoRecords()
        let loaded = records.first { $0.id == undoID }
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.status, .available)
    }

    // --- FingerprintService (SP-08) ---

    func testFingerprintServiceQuickHash() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("hash-test.txt", isDirectory: false)
        try Data("test content for hashing".utf8).write(to: file)

        let hash = try FingerprintService.quickHash(for: file, sizeBytes: 24)
        XCTAssertFalse(hash.isEmpty)
        // Same file should produce same hash
        let hash2 = try FingerprintService.quickHash(for: file, sizeBytes: 24)
        XCTAssertEqual(hash, hash2)
    }

    func testFingerprintServiceFullHash() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fullhash-test.txt", isDirectory: false)
        try Data("test content for full hashing".utf8).write(to: file)

        let hash = try FingerprintService.fullHash(for: file)
        XCTAssertFalse(hash.isEmpty)
        XCTAssertEqual(hash.count, 64, "SHA-256 hash should be 64 hex characters")
    }

    // --- ContentExtractor (SP-11, SP-12) ---

    func testContentExtractorExtractsTextContent() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.txt", isDirectory: false)
        try Data("This is a test document with some content.".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let extractor = ContentExtractor()
        let summaries = await extractor.summarize(files: records, privacyMode: .snippetsAI)
        let summary = summaries.first { $0.fileID == records.first { $0.url == file.standardizedFileURL }?.id }
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.textPreview?.contains("test document") ?? false)
    }

    // --- InboxManager (SB-03) ---

    func testInboxManagerDefaultURL() async {
        let manager = InboxManager()
        let url = await manager.defaultInboxURL()
        XCTAssertTrue(url.lastPathComponent == "Tidybyte Inbox")
    }

    func testInboxManagerCreatesInbox() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inboxURL = root.appendingPathComponent(AppIdentity.inboxFolderName, isDirectory: true)
        let manager = InboxManager()
        let created = try await manager.ensureInboxExists(at: inboxURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))
    }

    // --- PermissionManager (SM-01, SM-02, SM-03) ---

    func testPermissionManagerHomeFolderMode() async throws {
        // Home-folder roots must resolve to the configured home directory
        // (injected override; the real user home is never touched).
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let manager = PermissionManager(homeDirectoryOverride: home)
        let roots = try await manager.roots(for: .homeFolder, selectedFolders: [])
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first, home.standardizedFileURL)
    }

    func testPermissionManagerDeveloperMode() async throws {
        // Developer roots must be discovered under the configured home
        // directory, not the real user home.
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let developerDir = home.appendingPathComponent("Developer", isDirectory: true)
        try FileManager.default.createDirectory(at: developerDir, withIntermediateDirectories: true)
        let manager = PermissionManager(homeDirectoryOverride: home)
        let roots = try await manager.roots(for: .developerCleanup, selectedFolders: [])
        XCTAssertEqual(roots, [developerDir.standardizedFileURL])
    }

    func testPermissionManagerSelectedFoldersValidates() async {
        let manager = PermissionManager()
        do {
            _ = try await manager.roots(for: .selectedFolders, selectedFolders: [])
            XCTFail("Expected noSelectedFolders error")
        } catch let error as PermissionError {
            guard case .noSelectedFolders = error else {
                XCTFail("Expected noSelectedFolders error, got: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // --- KeychainStore (PS-03) ---

    func testKeychainStoreSaveAndLoadAPIKey() async throws {
        let store = KeychainStore(inMemory: true)
        let account = "test-\(UUID().uuidString)"
        let testKey = "sk-test-key-\(UUID().uuidString)"
        try await store.saveAPIKey(testKey, account: account)
        let loaded = try await store.loadAPIKey(account: account)
        XCTAssertEqual(loaded, testKey)
        try await store.deleteAPIKey(account: account)
    }

    // --- ProcessRunner ---

    func testProcessRunnerRunsEchoCommand() async {
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"], timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hello"))
    }

    func testProcessRunnerTimeoutProducesExit124() async {
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
        XCTAssertEqual(result.exitCode, 124, "Timed-out process should exit with code 124")
    }

    // --- FinderTagHelper ---

    func testFinderTagHelperWritesTags() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tagged.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)
        try FinderTagHelper.write(["TestTag", "Review"], to: file)
        // Verify the xattr was set
        let path = file.path
        let key = "com.apple.metadata:_kMDItemUserTags"
        let size = getxattr(path, key, nil, 0, 0, 0)
        XCTAssertGreaterThan(size, 0, "Tags should be written as extended attributes")
    }


    func testRiskLevelComparable() {
        XCTAssertTrue(RiskLevel.low < RiskLevel.medium)
        XCTAssertTrue(RiskLevel.medium < RiskLevel.high)
        XCTAssertTrue(RiskLevel.high < RiskLevel.forbidden)
    }

    // --- SortedPathSearch ---

    func testSortedPathSearchLowerBound() {
        let paths = ["/a/1", "/a/2", "/b/1", "/b/2", "/c/1"]
        XCTAssertEqual(SortedPathSearch.lowerBound(paths, "/b"), 2)
        XCTAssertEqual(SortedPathSearch.lowerBound(paths, "/a"), 0)
        XCTAssertEqual(SortedPathSearch.lowerBound(paths, "/d"), 5)
    }

    func testSortedPathSearchUpperBound() {
        let paths = ["/a/1", "/a/2", "/b/1", "/b/2", "/c/1"]
        XCTAssertEqual(SortedPathSearch.upperBound(paths, "/b/"), 4)
        XCTAssertEqual(SortedPathSearch.upperBound(paths, "/a/"), 2)
    }

    func testSortedPathSearchEmptyArray() {
        let paths: [String] = []
        XCTAssertEqual(SortedPathSearch.lowerBound(paths, "/a"), 0)
        XCTAssertEqual(SortedPathSearch.upperBound(paths, "/a"), 0)
    }

    // --- End-to-End Pipeline ---

    func testEndToEndScanProducesOutcomeAndPlan() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Create some test files
        try Data(repeating: 0, count: 1000).write(to: root.appendingPathComponent("file1.txt", isDirectory: false))
        try Data(repeating: 0, count: 1000).write(to: root.appendingPathComponent("file2.txt", isDirectory: false))
        // package.json makes the root a detected project root; node_modules only
        // matches as a build output inside a detected project root.
        try Data("{}".utf8).write(to: root.appendingPathComponent("package.json", isDirectory: false))
        let nmDir = root.appendingPathComponent("node_modules/pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: nmDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 5000).write(to: nmDir.appendingPathComponent("index.js", isDirectory: false))

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)
        let (outcome, plan) = try await orchestrator.scan(
            mode: .selectedFolders, selectedFolders: [root],
            providerSettings: ProviderSettings(), includeAI: false, posture: .balanced
        )
        XCTAssertGreaterThan(outcome.files.count, 0, "Should find files")
        XCTAssertGreaterThan(plan.actions.count, 0, "Should generate actions for node_modules")
        XCTAssertEqual(plan.status, .proposed)
    }

    func testEndToEndApproveExecuteUndo() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("delete-me.txt", isDirectory: false)
        try Data("delete this".utf8).write(to: file)

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)
        let (outcome, _) = try await orchestrator.scan(
            mode: .selectedFolders, selectedFolders: [root],
            providerSettings: ProviderSettings(), includeAI: false, posture: .balanced
        )

        // Build a simple plan with one action
        let fileRecord = outcome.files.first { $0.url == file.standardizedFileURL }!
        let action = PlannedAction(
            id: "test-action", planID: "test-plan", actionType: .moveToTrash,
            targets: [fileRecord.id], destination: nil, status: .approved,
            risk: .low, confidence: 0.9, reason: "test", userDecision: .approved,
            executedAt: nil, findingID: nil
        )

        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)
        let summary = await executor.execute(
            actions: [action], filesByID: [fileRecord.id: fileRecord]
        )
        XCTAssertFalse(summary.undoRecords.isEmpty, "Should produce undo records")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "File should be trashed")

        // Undo
        if let undoRecord = summary.undoRecords.first {
            let undoService = UndoManagerService(store: store, memory: memory)
            let restored = try await undoService.restore(undoRecord)
            XCTAssertEqual(restored.status, .restored)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "File should be restored")
        }
    }

    // MARK: - Dashboard Metrics Tests (DB-01 through DB-05)

    func testDashboardMetricsFromOutcome() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 1000).write(to: root.appendingPathComponent("a.txt", isDirectory: false))
        try Data(repeating: 0, count: 2000).write(to: root.appendingPathComponent("b.txt", isDirectory: false))

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)
        let (outcome, plan) = try await orchestrator.scan(
            mode: .selectedFolders, selectedFolders: [root],
            providerSettings: ProviderSettings(), includeAI: false, posture: .balanced
        )

        // DB-01: Files Seen metric — should reflect actual files crawled
        XCTAssertGreaterThanOrEqual(outcome.session.totalFilesSeen, 2, "Should see at least 2 files")

        // DB-02: Scanned bytes metric — should reflect actual file sizes
        XCTAssertGreaterThanOrEqual(outcome.session.totalBytesSeen, 3000, "Should scan at least 3000 bytes")

        // DB-03: Reviewable bytes from plan — should be non-negative
        XCTAssertGreaterThanOrEqual(plan.estimatedReclaimableBytes, 0, "Reviewable bytes should be >= 0")

        // DB-04: Projects count — should be 0 for plain text files
        XCTAssertEqual(outcome.projects.count, 0, "Plain text files should not form a project")

        // DB-05: Files array should contain the crawled files
        XCTAssertGreaterThanOrEqual(outcome.files.count, 2, "Should have at least 2 file records")
    }

    func testDashboardSectionsComputedCorrectly() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // package.json makes "project" a detected project root so node_modules
        // inside it is a valid project-bound build output.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("project", isDirectory: true), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("project/package.json", isDirectory: false))
        let nmDir = root.appendingPathComponent("project/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nmDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 5000).write(to: nmDir.appendingPathComponent("index.js", isDirectory: false))

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)
        let (outcome, _) = try await orchestrator.scan(
            mode: .selectedFolders, selectedFolders: [root],
            providerSettings: ProviderSettings(), includeAI: false, posture: .balanced
        )

        // Dashboard sections should group findings by category
        let sections = Dictionary(grouping: outcome.findings, by: \.category)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.bytesReclaimable } }
            .sorted { $0.value > $1.value }
        // Should have at least one section (developerArtifact from node_modules)
        XCTAssertFalse(sections.isEmpty, "Dashboard should have at least one section")
    }

    // MARK: - Settings Persistence Tests (ST-01 through ST-05)
    // Each test writes to an isolated UserDefaults suite and removes the whole
    // domain in cleanup, so UserDefaults.standard (and the app's real keys) are
    // never touched or polluted.

    func testSettingsPersistenceScanMode() throws {
        let suiteName = "TidybyteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(ScanMode.homeFolder.rawValue, forKey: "selectedMode")
        let loaded = defaults.string(forKey: "selectedMode").flatMap(ScanMode.init)
        XCTAssertEqual(loaded, .homeFolder)
    }

    func testSettingsPersistenceCleanupPosture() throws {
        let suiteName = "TidybyteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(CleanupPosture.aggressive.rawValue, forKey: "cleanupPosture")
        let loaded = defaults.string(forKey: "cleanupPosture").flatMap(CleanupPosture.init)
        XCTAssertEqual(loaded, .aggressive)
    }

    func testSettingsPersistencePrivacyMode() throws {
        let suiteName = "TidybyteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(PrivacyMode.snippetsAI.rawValue, forKey: "privacyMode")
        let loaded = defaults.string(forKey: "privacyMode").flatMap(PrivacyMode.init)
        XCTAssertEqual(loaded, .snippetsAI)
    }

    func testSettingsPersistenceIncludeAI() throws {
        let suiteName = "TidybyteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "includeAI")
        XCTAssertTrue(defaults.bool(forKey: "includeAI"))
    }

    func testSettingsPersistenceProviderSettings() throws {
        let suiteName = "TidybyteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("TestProvider", forKey: "providerName")
        defaults.set("https://api.test.com", forKey: "apiBaseURL")
        defaults.set("gpt-4", forKey: "textModel")
        defaults.set(4000, forKey: "maxTokens")
        defaults.set(0.7, forKey: "temperature")

        XCTAssertEqual(defaults.string(forKey: "providerName"), "TestProvider")
        XCTAssertEqual(defaults.string(forKey: "apiBaseURL"), "https://api.test.com")
        XCTAssertEqual(defaults.string(forKey: "textModel"), "gpt-4")
        XCTAssertEqual(defaults.integer(forKey: "maxTokens"), 4000)
        XCTAssertEqual(defaults.double(forKey: "temperature"), 0.7, accuracy: 0.01)
    }

    // MARK: - NL Commands: Additional Patterns (NL-03 through NL-15)

    func testPlannerAgentNaturalLanguagePythonCachesCommand() async {
        let planner = PlannerAgent()
        let pyRecord = makeFileRecord(id: "p1", path: "/Users/me/project/__pycache__/module.pyc", sizeBytes: 1000)
        let otherRecord = makeFileRecord(id: "o1", path: "/Users/me/Documents/file.txt", sizeBytes: 500)
        let filesByID = [pyRecord.id: pyRecord, otherRecord.id: otherRecord]
        let rec1 = makeRecommendation(id: "r1", targetID: "p1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "o1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("clean python caches", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1)
        XCTAssertEqual(filtered.actions.first?.targets.first, "p1")
    }

    func testPlannerAgentNaturalLanguageBigFilesCommand() async {
        let planner = PlannerAgent()
        let bigRecord = makeFileRecord(id: "b1", path: "/Users/me/big-video.mp4", sizeBytes: 2_000_000_000)
        let smallRecord = makeFileRecord(id: "s1", path: "/Users/me/small.txt", sizeBytes: 100)
        let filesByID = [bigRecord.id: bigRecord, smallRecord.id: smallRecord]
        let rec1 = makeRecommendation(id: "r1", targetID: "b1", action: .moveToTrash, risk: .low, confidence: 0.8)
        let rec2 = makeRecommendation(id: "r2", targetID: "s1", action: .moveToTrash, risk: .low, confidence: 0.8)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("show big files", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1)
        XCTAssertEqual(filtered.actions.first?.targets.first, "b1")
    }

    func testPlannerAgentNaturalLanguageDuplicatesCommand() async {
        let planner = PlannerAgent()
        let f1 = makeFileRecord(id: "f1", path: "/Users/me/a.txt", sizeBytes: 100)
        let f2 = makeFileRecord(id: "f2", path: "/Users/me/b.txt", sizeBytes: 100)
        let filesByID = [f1.id: f1, f2.id: f2]
        // Two recommendations targeting the same file (simulating duplicate findings)
        let rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "f1", action: .moveToTrash, risk: .low)
        let rec3 = makeRecommendation(id: "r3", targetID: "f2", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2, rec3], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("show duplicates", existingPlan: plan, filesByID: filesByID)
        // f1 appears in multiple actions, so it should be kept
        XCTAssertTrue(filtered.actions.contains { $0.targets.contains("f1") })
    }

    func testPlannerAgentNaturalLanguageOldFilesCommand() async {
        let planner = PlannerAgent()
        var oldRecord = makeFileRecord(id: "o1", path: "/Users/me/old-file.txt", sizeBytes: 100)
        oldRecord.modifiedAt = Calendar.current.date(byAdding: .day, value: -60, to: Date())
        let newRecord = makeFileRecord(id: "n1", path: "/Users/me/new-file.txt", sizeBytes: 100)
        let filesByID = [oldRecord.id: oldRecord, newRecord.id: newRecord]
        let rec1 = makeRecommendation(id: "r1", targetID: "o1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "n1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("clean old files", existingPlan: plan, filesByID: filesByID)
        XCTAssertTrue(filtered.actions.contains { $0.targets.contains("o1") })
        XCTAssertFalse(filtered.actions.contains { $0.targets.contains("n1") })
    }

    func testPlannerAgentNaturalLanguageSafeFiltersLowRisk() async {
        let planner = PlannerAgent()
        let f1 = makeFileRecord(id: "f1", path: "/Users/me/a.txt", sizeBytes: 100)
        let f2 = makeFileRecord(id: "f2", path: "/Users/me/b.txt", sizeBytes: 100)
        let filesByID = [f1.id: f1, f2.id: f2]
        let rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        let rec2 = makeRecommendation(id: "r2", targetID: "f2", action: .moveToTrash, risk: .high, confidence: 0.9)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: filesByID)
        XCTAssertEqual(plan.actions.count, 2)

        let filtered = await planner.planForNaturalLanguageCommand("be safe", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.count, 1, "Safe command should filter to low-risk only")
        XCTAssertEqual(filtered.actions.first?.risk, .low)
    }

    func testPlannerAgentNaturalLanguageDeleteChangesActionType() async {
        let planner = PlannerAgent()
        let f1 = makeFileRecord(id: "f1", path: "/Users/me/a.txt", sizeBytes: 100)
        let filesByID = [f1.id: f1]
        let rec = makeRecommendation(id: "r1", targetID: "f1", action: .tag, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec], filesByID: filesByID)
        XCTAssertEqual(plan.actions.first?.actionType, .tag)

        let filtered = await planner.planForNaturalLanguageCommand("delete this", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(filtered.actions.first?.actionType, .moveToTrash)
    }

    // MARK: - ActionExecutor: Additional Action Types (EX-05 through EX-10)

    func testActionExecutorTagAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tag-test.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        let action = PlannedAction(
            id: "tag-1", planID: "p1", actionType: .tag, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9,
            reason: "test tag", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertTrue(summary.failures.isEmpty, "Tag action should succeed")
        XCTAssertFalse(summary.undoRecords.isEmpty, "Tag action should produce undo record")
    }

    func testActionExecutorCreateAliasAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("alias-test.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)
        let aliasDest = root.appendingPathComponent("aliases", isDirectory: true)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        let action = PlannedAction(
            id: "alias-1", planID: "p1", actionType: .createAlias, targets: [record.id],
            destination: aliasDest, status: .approved, risk: .low, confidence: 0.9,
            reason: "test alias", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertTrue(summary.failures.isEmpty, "Create alias should succeed")
        XCTAssertFalse(summary.undoRecords.isEmpty, "Create alias should produce undo record")
    }

    func testActionExecutorArchiveAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("archive-test.txt", isDirectory: false)
        try Data("content to archive".utf8).write(to: file)
        let archiveDest = root.appendingPathComponent("archives", isDirectory: true)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        let action = PlannedAction(
            id: "archive-1", planID: "p1", actionType: .archive, targets: [record.id],
            destination: archiveDest, status: .approved, risk: .low, confidence: 0.9,
            reason: "test archive", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertTrue(summary.failures.isEmpty, "Archive should succeed")
        XCTAssertFalse(summary.undoRecords.isEmpty, "Archive should produce undo records")
        // Original should be trashed
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Original should be trashed after archive")
    }

    // MARK: - UndoManagerService: Additional Undo Types (UN-11 through UN-14)

    func testUndoManagerServiceRestoreTagAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tag-undo.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)

        // Simulate a tag operation log
        let logID = UUID().uuidString
        let log = OperationLog(
            id: logID, plannedActionID: "p1", operationType: .tag,
            beforeState: ["tags": "OldTag", "path": file.path],
            afterState: ["tags": "OldTag,NewTag"],
            executorVersion: "1.0", result: "tagged", error: nil, timestamp: Date()
        )
        try await store.saveOperationLog(log)

        let undo = UndoRecord(
            id: UUID().uuidString, operationLogID: logID, inverseAction: .tag,
            restoreURL: file, trashURL: nil,
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            status: .available
        )
        try await store.saveUndoRecord(undo)

        let restored = try await undoService.restore(undo)
        XCTAssertEqual(restored.status, .restored)
    }
    // MARK: - FileCrawler: Edge Cases (SP-04)

    func testFileCrawlerHandlesHiddenFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hidden = root.appendingPathComponent(".hidden-file", isDirectory: false)
        try Data("secret".utf8).write(to: hidden)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == hidden.standardizedFileURL }
        XCTAssertNotNil(record, "Hidden files should be found by crawler")
        XCTAssertTrue(record?.fileName.hasPrefix(".") ?? false, "Hidden file name should start with dot")
    }

    func testFileCrawlerHandlesEmptyDirectory() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let emptyDir = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let crawler = FileCrawler()
        let (records, errors) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let dirRecord = records.first { $0.url == emptyDir.standardizedFileURL }
        XCTAssertNotNil(dirRecord, "Empty directory should be found")
        XCTAssertEqual(errors, 0, "No errors expected for empty directory")
    }

    // MARK: - ContentExtractor: Additional Types (SP-13, SP-14)

    func testContentExtractorHandlesMissingFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missingURL = root.appendingPathComponent("nonexistent.txt", isDirectory: false)

        let extractor = ContentExtractor()
        let summaries = await extractor.summarize(
            files: [FileRecord(
                id: "missing", scanSessionID: "test", source: .local, url: missingURL,
                displayPath: missingURL.path, fileName: "nonexistent.txt", fileExtension: "txt",
                utiDescription: nil, kind: .regularFile, sizeBytes: 0,
                createdAt: nil, modifiedAt: nil, lastOpenedAt: nil,
                owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
                isPackage: false, isCloudPlaceholder: false, cloudProvider: nil,
                finderTags: [], spotlightMetadata: [:], riskFlags: [],
                identity: FileIdentity(deviceIdentifier: nil, inodeIdentifier: nil, resourceIdentifier: nil),
                capabilities: []
            )],
            privacyMode: .localOnly
        )
        // A missing file cannot be read, so extraction must not crash and
        // must not fabricate a summary for it.
        XCTAssertTrue(summaries.isEmpty, "A missing file should not produce a summary")
    }

    // MARK: - DomainModels: Enum Exhaustiveness
    // Per-enum count assertions were removed — brittle change-detectors that
    // break on any legitimate addition. Exhaustive switching is enforced at
    // compile time everywhere an enum is consumed; the display-name tests below
    // (and in ConfigWaveTests) cover per-case behavior.

    // MARK: - Int64 formattedByteCount

    func testFormattedByteCount() {
        XCTAssertEqual(Int64(0).formattedByteCount, "0 bytes")
        XCTAssertEqual(Int64(1024).formattedByteCount, "1 KB")
        XCTAssertEqual(Int64(1_048_576).formattedByteCount, "1 MB")
    }

    // MARK: - ProviderSettings defaults

    func testProviderSettingsDefaults() {
        let settings = ProviderSettings()
        // Default privacy mode is localOnly per DESIGN.md (privacy by default);
        // the user opts into metadata sharing explicitly.
        XCTAssertEqual(settings.privacyMode, .localOnly)
        XCTAssertGreaterThan(settings.maxTokens, 0)
        XCTAssertGreaterThanOrEqual(settings.temperature, 0)
        XCTAssertLessThanOrEqual(settings.temperature, 1)
    }

    // MARK: - Dashboard: Treemap & Relationship Graph (DB-06 through DB-09)

    func testTreemapSectionsSortedByBytes() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // package.json makes "project" a detected project root so node_modules
        // inside it is a valid project-bound build output.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("project", isDirectory: true), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("project/package.json", isDirectory: false))
        let nmDir = root.appendingPathComponent("project/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nmDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 5000).write(to: nmDir.appendingPathComponent("index.js", isDirectory: false))

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)
        let (outcome, _) = try await orchestrator.scan(
            mode: .selectedFolders, selectedFolders: [root],
            providerSettings: ProviderSettings(), includeAI: false, posture: .balanced
        )

        // Sections should be sorted by bytes (descending)
        let sections = Dictionary(grouping: outcome.findings, by: \.category)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.bytesReclaimable } }
            .sorted { $0.value > $1.value }
        if sections.count > 1 {
            XCTAssertGreaterThanOrEqual(sections[0].value, sections[1].value, "Sections should be sorted by bytes descending")
        }
    }

    func testRelationshipEdgesFromDuplicates() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "duplicate content for edge test"
        try Data(content.utf8).write(to: root.appendingPathComponent("dup1.txt", isDirectory: false))
        try Data(content.utf8).write(to: root.appendingPathComponent("dup2.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(files: records, sessionID: "scan")
        XCTAssertFalse(analysis.edges.isEmpty, "Duplicate files should produce relationship edges")
        XCTAssertEqual(analysis.edges.first?.edgeType, .duplicate)
    }

    func testRelationshipEdgesFromProjects() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("package.json", isDirectory: false))
        try Data("console.log('hi')".utf8).write(to: root.appendingPathComponent("index.js", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = ProjectDetector()
        let projects = await detector.detectProjects(in: records)
        let edges = await detector.buildEdges(files: records, projects: projects)
        XCTAssertFalse(edges.isEmpty, "Project files should produce sameProject edges")
    }

    // MARK: - Undo System: Regret Reasons (UN-03 through UN-08)

    func testUndoManagerServiceRegretReasons() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let reasons = ["Needed later", "Misclassified", "Should have archived", "Wrong project", "Too aggressive"]
        for (index, reason) in reasons.enumerated() {
            // Unique path per iteration so the same Trash item is never reused.
            let file = root.appendingPathComponent("regret-\(index).txt", isDirectory: false)
            try Data("content \(index)".utf8).write(to: file)
            let trashURL = try FixtureTrash().trashItem(at: file)

            let logID = UUID().uuidString
            let log = OperationLog(
                id: logID, plannedActionID: "p\(index)", operationType: .moveToTrash,
                beforeState: ["path": file.path, "file_id": "test-file-\(index)"],
                afterState: ["trash_path": trashURL?.path ?? ""],
                executorVersion: "1.0", result: "moved_to_trash", error: nil, timestamp: Date()
            )
            try await store.saveOperationLog(log)

            let undo = UndoRecord(
                id: UUID().uuidString, operationLogID: logID, inverseAction: .restore,
                restoreURL: file, trashURL: trashURL,
                validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                status: .available
            )
            try await store.saveUndoRecord(undo)

            do {
                let restored = try await undoService.restore(undo, regretReason: reason)
                XCTAssertEqual(restored.status, .restored, "Restore with reason '\(reason)' should succeed")
                XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                              "Restored file should be back in the temp root (not left in Trash)")
            } catch {
                // Best-effort cleanup: pull the item back out of Trash so the
                // test never leaves files in the user's Trash.
                if let trashURL, FileManager.default.fileExists(atPath: trashURL.path) {
                    try? FileManager.default.moveItem(at: trashURL, to: file)
                }
                throw error
            }
        }

        // Verify regret events were recorded
        let regretEvents = try await store.loadMemoryRules()
        XCTAssertTrue(regretEvents.count >= reasons.count, "Should have regret rules for each reason")
    }

    // MARK: - Undo System: Batch Restore (UN-01)

    func testUndoManagerServiceBatchRestore() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Create multiple files and trash them
        var undoRecords: [UndoRecord] = []
        for i in 0..<3 {
            let file = root.appendingPathComponent("batch-\(i).txt", isDirectory: false)
            try Data("content \(i)".utf8).write(to: file)
            let trashURL = try FixtureTrash().trashItem(at: file)

            let logID = UUID().uuidString
            let log = OperationLog(
                id: logID, plannedActionID: "p\(i)", operationType: .moveToTrash,
                beforeState: ["path": file.path, "file_id": "file-\(i)"],
                afterState: ["trash_path": trashURL?.path ?? ""],
                executorVersion: "1.0", result: "moved_to_trash", error: nil, timestamp: Date()
            )
            try await store.saveOperationLog(log)

            let undo = UndoRecord(
                id: UUID().uuidString, operationLogID: logID, inverseAction: .restore,
                restoreURL: file, trashURL: trashURL,
                validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                status: .available
            )
            try await store.saveUndoRecord(undo)
            undoRecords.append(undo)
        }

        let (restored, failureCount) = await undoService.restoreBatch(undoRecords)
        XCTAssertEqual(restored.count, 3, "All 3 items should be restored")
        XCTAssertEqual(failureCount, 0, "No failures expected")
    }

    // MARK: - Dashboard: Forecast (DB-10)

    func testSpaceForecasterWithGrowthData() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("forecast.sqlite"))

        // Create snapshots showing growth over 10 days
        for i in 0..<10 {
            let snapshot = StorageSnapshot(
                id: "snap-\(i)",
                createdAt: Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date(),
                totalBytes: Int64(500_000_000_000 + i * 1_000_000_000), // 500GB + 1GB/day
                bytesByCategory: [:],
                bytesByRootPath: [:],
                bytesByProject: [:],
                removedBytesThroughApp: 0
            )
            try await store.saveStorageSnapshot(snapshot)
        }

        let forecaster = SpaceForecaster(store: store)
        let capacity: Int64 = 1_000_000_000_000 // 1TB
        let forecast = try await forecaster.forecast(diskCapacity: capacity)
        XCTAssertNotNil(forecast, "Should produce a forecast with sufficient data")
        XCTAssertNotNil(forecast?.dailyGrowthRate)
        XCTAssertNotNil(forecast?.message)
    }

    func testSpaceForecasterWithNoGrowth() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("forecast-flat.sqlite"))

        // Create snapshots with no growth
        for i in 0..<10 {
            let snapshot = StorageSnapshot(
                id: "snap-\(i)",
                createdAt: Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date(),
                totalBytes: 500_000_000_000, // constant 500GB
                bytesByCategory: [:],
                bytesByRootPath: [:],
                bytesByProject: [:],
                removedBytesThroughApp: 0
            )
            try await store.saveStorageSnapshot(snapshot)
        }

        let forecaster = SpaceForecaster(store: store)
        let capacity: Int64 = 1_000_000_000_000
        let forecast = try await forecaster.forecast(diskCapacity: capacity)
        // Flat snapshots produce a zero-growth forecast with a stable message,
        // never a nil result (the nil case needs fewer than 2 snapshots).
        let unwrapped = try XCTUnwrap(forecast, "Flat history should still yield a forecast")
        XCTAssertEqual(unwrapped.dailyGrowthRate, 0, "No growth should have zero growth rate")
        XCTAssertFalse(unwrapped.message.isEmpty, "Zero-growth forecast should carry a message")
    }

    // MARK: - ActionExecutor: Failed Action Tracking (H-03)

    func testActionExecutorTracksFailedActionIDs() async throws {
        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        // Try to execute an action with a missing target
        let action = PlannedAction(
            id: "fail-1", planID: "p1", actionType: .moveToTrash, targets: ["nonexistent-id"],
            destination: nil, status: .approved, risk: .low, confidence: 0.9,
            reason: "test", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [:])
        XCTAssertTrue(summary.failedActionIDs.contains("fail-1"), "Failed action should be tracked")
        XCTAssertFalse(summary.failures.isEmpty, "Should have failure messages")
    }

    // MARK: - PlannerAgent: Dedup with findingID (L-12)

    func testPlannerAgentPreservesCrossCategoryFindings() async {
        let planner = PlannerAgent()
        // Same target, same action, but different finding IDs
        let rec1 = Recommendation(
            id: "r1", findingID: "duplicate-finding", actionType: .moveToTrash,
            targetFileIDs: ["f1"], confidence: 0.9, risk: .low,
            reason: "duplicate file", expectedBytesReclaimed: 1000,
            requiresConfirmation: false, llmTraceID: nil, policyTraceID: nil
        )
        let rec2 = Recommendation(
            id: "r2", findingID: "large-file-finding", actionType: .moveToTrash,
            targetFileIDs: ["f1"], confidence: 0.8, risk: .low,
            reason: "large file", expectedBytesReclaimed: 1000,
            requiresConfirmation: false, llmTraceID: nil, policyTraceID: nil
        )
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: [:])
        XCTAssertEqual(plan.actions.count, 2, "Different finding IDs = separate actions (cross-category preserved)")
    }

    // MARK: - MemoryEngine: Pattern Detection (ML-03)

    func testMemoryEngineDetectsRejectionPatterns() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)

        // Create 3+ rejections for the same action type and directory
        var actions: [PlannedAction] = []
        for i in 0..<4 {
            let file = makeFileRecord(id: "f\(i)", path: "/tmp/test/file\(i).txt", sizeBytes: 100)
            let action = PlannedAction(
                id: "a\(i)", planID: "p1", actionType: .moveToTrash, targets: [file.id],
                destination: nil, status: .rejected, risk: .low, confidence: 0.9,
                reason: "test", userDecision: .neverDoThisHere, executedAt: nil, findingID: nil
            )
            actions.append(action)
        }

        let filesByID = Dictionary(uniqueKeysWithValues: actions.enumerated().map { i, action in
            (action.targets[0], makeFileRecord(id: action.targets[0], path: "/tmp/test/file\(i).txt", sizeBytes: 100))
        })

        try await memory.detectPatterns(from: actions, filesByID: filesByID)
        let rules = try await store.loadMemoryRules()
        let neverRules = rules.filter { $0.ruleType == .never }
        XCTAssertFalse(neverRules.isEmpty, "3+ rejections should auto-generate a 'never' rule")
    }

    func testMemoryEngineDetectsApprovalPatterns() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)

        var actions: [PlannedAction] = []
        for i in 0..<4 {
            let file = makeFileRecord(id: "f\(i)", path: "/tmp/test/file\(i).txt", sizeBytes: 100)
            let action = PlannedAction(
                id: "a\(i)", planID: "p1", actionType: .moveToTrash, targets: [file.id],
                destination: nil, status: .approved, risk: .low, confidence: 0.9,
                reason: "test", userDecision: .alwaysDoThis, executedAt: nil, findingID: nil
            )
            actions.append(action)
        }

        let filesByID = Dictionary(uniqueKeysWithValues: actions.enumerated().map { i, action in
            (action.targets[0], makeFileRecord(id: action.targets[0], path: "/tmp/test/file\(i).txt", sizeBytes: 100))
        })

        try await memory.detectPatterns(from: actions, filesByID: filesByID)
        let rules = try await store.loadMemoryRules()
        let alwaysRules = rules.filter { $0.ruleType == .always }
        XCTAssertFalse(alwaysRules.isEmpty, "3+ approvals should auto-generate an 'always' rule")
    }

    // MARK: - MemoryEngine: Regret Recording (ML-04)

    func testMemoryEngineRecordRegret() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)

        try await memory.recordRegret(
            operationLogID: "log-1",
            restoredFileID: "file-1",
            reason: "Needed later"
        )

        let rules = try await store.loadMemoryRules()
        let regretRules = rules.filter { $0.source == "regret" }
        XCTAssertFalse(regretRules.isEmpty, "Regret should create a memory rule")
        XCTAssertEqual(regretRules.first?.ruleType, .never, "Regret rule should be 'never' type")
    }

    // MARK: - NL Commands: Compound Commands (M-15 fix)

    func testPlannerAgentNLCompoundOldDownloads() async {
        let planner = PlannerAgent()
        let oldDownload = makeFileRecord(id: "d1", path: "/Users/me/Downloads/old.zip", sizeBytes: 1000)
        var old = oldDownload
        old.modifiedAt = Calendar.current.date(byAdding: .day, value: -60, to: Date())
        let newDownload = makeFileRecord(id: "d2", path: "/Users/me/Downloads/new.zip", sizeBytes: 1000)
        let oldOther = makeFileRecord(id: "o1", path: "/Users/me/Documents/old.txt", sizeBytes: 1000)
        var oldDoc = oldOther
        oldDoc.modifiedAt = Calendar.current.date(byAdding: .day, value: -60, to: Date())
        let filesByID = [old.id: old, newDownload.id: newDownload, oldDoc.id: oldDoc]
        let rec1 = makeRecommendation(id: "r1", targetID: "d1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "d2", action: .moveToTrash, risk: .low)
        let rec3 = makeRecommendation(id: "r3", targetID: "o1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2, rec3], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("old downloads", existingPlan: plan, filesByID: filesByID)
        // Should only match old files in Downloads (d1), not new downloads or old files elsewhere
        XCTAssertEqual(filtered.actions.count, 1, "Compound 'old downloads' should match only old files in Downloads")
        XCTAssertEqual(filtered.actions.first?.targets.first, "d1")
    }

    func testPlannerAgentNLCompoundLargeCaches() async {
        let planner = PlannerAgent()
        let largeCache = makeFileRecord(id: "c1", path: "/Users/me/Library/Caches/big.dat", sizeBytes: 200_000_000)
        let smallCache = makeFileRecord(id: "c2", path: "/Users/me/Library/Caches/small.dat", sizeBytes: 1000)
        let largeOther = makeFileRecord(id: "o1", path: "/Users/me/Documents/big.pdf", sizeBytes: 200_000_000)
        let filesByID = [largeCache.id: largeCache, smallCache.id: smallCache, largeOther.id: largeOther]
        let rec1 = makeRecommendation(id: "r1", targetID: "c1", action: .moveToTrash, risk: .low)
        let rec2 = makeRecommendation(id: "r2", targetID: "c2", action: .moveToTrash, risk: .low)
        let rec3 = makeRecommendation(id: "r3", targetID: "o1", action: .moveToTrash, risk: .low)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2, rec3], filesByID: filesByID)

        let filtered = await planner.planForNaturalLanguageCommand("large caches", existingPlan: plan, filesByID: filesByID)
        // Intent grammar splits "large caches" into two OR scopes: largerThan
        // (100MB+, since "files" is absent) and caches. c1 matches both, o1
        // matches the size scope — OR logic keeps both. The compound AND
        // reading was never implemented; assert the documented OR behavior.
        XCTAssertTrue(filtered.actions.contains { $0.targets.contains("c1") }, "Large cache file should be matched")
        XCTAssertTrue(filtered.actions.contains { $0.targets.contains("o1") }, "Large non-cache file matches the size scope under OR logic")
    }

    // MARK: - Undo System: More Undo Types (UN-11 through UN-14)
    // (Raw UserDefaults round-trip tests for provider settings were removed as
    // redundant with testSettingsPersistenceProviderSettings above.)

    func testUndoManagerServiceRestoreCreateAliasAction() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let aliasFile = root.appendingPathComponent("test.alias", isDirectory: false)
        try Data("alias".utf8).write(to: aliasFile)

        let logID = UUID().uuidString
        var afterState: [String: String] = ["alias_path": aliasFile.path]
        if let identity = FileArtifactIdentity.capture(at: aliasFile) {
            afterState["artifact_identity"] = identity.encodedString
        }
        let log = OperationLog(
            id: logID, plannedActionID: "p1", operationType: .createAlias,
            beforeState: ["path": "/tmp/original.txt"],
            afterState: afterState,
            executorVersion: "1.0", result: "alias_created", error: nil, timestamp: Date()
        )
        try await store.saveOperationLog(log)

        let undo = UndoRecord(
            id: UUID().uuidString, operationLogID: logID, inverseAction: .moveToTrash,
            restoreURL: aliasFile, trashURL: nil,
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            status: .available
        )
        try await store.saveUndoRecord(undo)

        let undoService = UndoManagerService(store: store, memory: memory)
        let restored = try await undoService.restore(undo)
        XCTAssertEqual(restored.status, .restored)
        // Alias file should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: aliasFile.path), "Alias should be removed on undo")
    }

    func testUndoManagerServiceRestoreCreateSymlinkAction() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("target.txt", isDirectory: false)
        try Data("target".utf8).write(to: target)
        let link = root.appendingPathComponent("link.txt", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let logID = UUID().uuidString
        var afterState: [String: String] = ["link_path": link.path]
        if let identity = FileArtifactIdentity.capture(at: link) {
            afterState["artifact_identity"] = identity.encodedString
        }
        let log = OperationLog(
            id: logID, plannedActionID: "p1", operationType: .createSymlink,
            beforeState: ["path": target.path],
            afterState: afterState,
            executorVersion: "1.0", result: "symlink_created", error: nil, timestamp: Date()
        )
        try await store.saveOperationLog(log)

        let undo = UndoRecord(
            id: UUID().uuidString, operationLogID: logID, inverseAction: .moveToTrash,
            restoreURL: link, trashURL: nil,
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            status: .available
        )
        try await store.saveUndoRecord(undo)

        let undoService = UndoManagerService(store: store, memory: memory)
        let restored = try await undoService.restore(undo)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path), "Symlink should be removed on undo")
    }

    // MARK: - Dashboard: Forecast Edge Cases (DB-10)

    func testSpaceForecasterWithInsufficientData() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("forecast-sparse.sqlite"))

        // Exactly two snapshots with growth — the minimum viable dataset for a
        // forecast (fewer than 2 returns nil, covered elsewhere).
        for i in 0..<2 {
            let snapshot = StorageSnapshot(
                id: "snap-\(i)",
                createdAt: Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date(),
                totalBytes: Int64(500_000_000_000 + (1 - i) * 1_000_000_000),
                bytesByCategory: [:],
                bytesByRootPath: [:],
                bytesByProject: [:],
                removedBytesThroughApp: 0
            )
            try await store.saveStorageSnapshot(snapshot)
        }

        let forecaster = SpaceForecaster(store: store)
        let capacity: Int64 = 1_000_000_000_000
        // Inject the volume state directly: 1 TB capacity with 400 GB available
        // (600 GB used), so the 95%-full projection is deterministic and does not
        // depend on the real disk's free space.
        let forecast = try await forecaster.forecast(capacity: capacity, availableBytes: 400_000_000_000)
        // 2 snapshots clear the guard; 1 GB/day growth yields a real forecast.
        let unwrapped = try XCTUnwrap(forecast, "Two snapshots with growth should produce a forecast")
        XCTAssertEqual(unwrapped.dailyGrowthRate, 1_000_000_000)
        XCTAssertFalse(unwrapped.message.isEmpty, "Forecast should carry a message")
        XCTAssertNotNil(unwrapped.daysUntil95PercentFull, "Forecast should project a 95% full date")
    }

    // MARK: - Menu Bar: Underlying Logic (MB-01 through MB-07)

    func testMenuBarQuickScanDownloadsLogic() async throws {
        // The menu-bar "Quick Scan Downloads" action resolves the Downloads
        // folder and scans it in selectedFolders mode. Test the same logic
        // against a controlled temp Downloads folder so the real one is never
        // scanned or modified.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloadsDir = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let installer = downloadsDir.appendingPathComponent("installer.dmg", isDirectory: false)
        try Data(repeating: 0, count: 2000).write(to: installer)

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)

        // Quick Scan Downloads scans the Downloads folder via selectedFolders mode.
        let (outcome, plan) = try await orchestrator.scan(
            mode: .selectedFolders, selectedFolders: [downloadsDir],
            providerSettings: ProviderSettings(), includeAI: false, posture: .balanced
        )
        XCTAssertGreaterThan(outcome.files.count, 0, "Quick scan should crawl the Downloads folder")
        XCTAssertTrue(outcome.files.contains { $0.url == installer.standardizedFileURL },
                      "Quick scan should find the installer file")
        XCTAssertNotNil(plan, "Quick Scan should produce a plan")
    }

    // MARK: - Sidebar Controls (SB-01 through SB-06)
    // Sidebar binding round-trips through UserDefaults were removed: they
    // exercised Foundation's defaults API against keys the app never reads.
    // Real sidebar behavior is covered by AppViewModelTests (isolated default
    // suites + real model mutations).

    // MARK: - Onboarding Flow (ON-01 through ON-10)
    // The onboarding "should show" tests read a synthetic UserDefaults key and
    // asserted on their own input; the actual gate is loadSettings() +
    // selectedFolders, covered by AppViewModelTests.

    // MARK: - Organization Suggestions (SP-25)

    func testOrganizationPlannerSuggestsAliasForInbox() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent(AppIdentity.inboxFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let file = inbox.appendingPathComponent("report.pdf", isDirectory: false)
        try Data(repeating: 0, count: 1000).write(to: file)
        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let planner = OrganizationPlanner()
        let (_, recs) = await planner.suggestOrganization(files: records, sessionID: "scan")
        // Inbox files should get alias recommendations
        let aliasRecs = recs.filter { $0.actionType == .createAlias }
        XCTAssertFalse(aliasRecs.isEmpty, "Inbox files should get alias recommendations")
    }

    // MARK: - ContentExtractor: PDF and Image (SP-12, SP-14)

    func testContentExtractorHandlesPDF() async throws {
        // A real one-page PDF with extractable text (CoreGraphics + CoreText).
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfFile = root.appendingPathComponent("test.pdf", isDirectory: false)
        try TestFileFixtures.makePDF(at: pdfFile, text: "Invoice for cleanup test")

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let extractor = ContentExtractor()
        let summaries = await extractor.summarize(files: records, privacyMode: .snippetsAI)
        let summary = try XCTUnwrap(summaries.first, "A readable PDF should produce a text summary")
        XCTAssertTrue(summary.textPreview?.contains("Invoice for cleanup test") == true,
                      "PDF text should be extracted into the summary preview")
    }

    func testContentExtractorHandlesImage() async throws {
        // A real 10x10 PNG readable by ImageIO.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let imgFile = root.appendingPathComponent("test.png", isDirectory: false)
        try TestFileFixtures.makePNG(at: imgFile, width: 10, height: 10)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let extractor = ContentExtractor()
        let summaries = await extractor.summarize(files: records, privacyMode: .snippetsAI)
        let summary = try XCTUnwrap(summaries.first, "A readable image should produce a summary with metadata labels")
        XCTAssertTrue(summary.imageLabels.contains("image"), "Image summaries should carry an 'image' label")
        XCTAssertTrue(summary.imageLabels.contains(where: { $0.hasPrefix("10x10") }),
                      "Image summaries should carry pixel dimensions")
    }

    // MARK: - ActionExecutor: More Action Types (EX-06 through EX-10)

    func testActionExecutorCreateSymlinkAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("symlink-target.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)
        let linkDest = root.appendingPathComponent("links", isDirectory: true)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        let action = PlannedAction(
            id: "symlink-1", planID: "p1", actionType: .createSymlink, targets: [record.id],
            destination: linkDest, status: .approved, risk: .low, confidence: 0.9,
            reason: "test symlink", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertTrue(summary.failures.isEmpty, "Create symlink should succeed")
        XCTAssertFalse(summary.undoRecords.isEmpty, "Create symlink should produce undo record")
    }

    func testActionExecutorRejectsHighRiskAction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("high-risk.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        let action = PlannedAction(
            id: "high-1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .high, confidence: 0.9,
            reason: "test high risk", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        // High-risk destructive actions should be rejected by safety auditor
        XCTAssertFalse(summary.failures.isEmpty, "High-risk action should fail safety audit")
    }

    // MARK: - PlannerAgent: Summary Generation (PR-13)

    func testPlannerAgentSummaryWithMixedRisks() async {
        let planner = PlannerAgent()
        let rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        let rec2 = makeRecommendation(id: "r2", targetID: "f2", action: .moveToTrash, risk: .medium, confidence: 0.8)
        let rec3 = makeRecommendation(id: "r3", targetID: "f3", action: .moveToTrash, risk: .high, confidence: 0.7)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2, rec3], filesByID: [:])
        XCTAssertTrue(plan.summary.contains("3"), "Summary should mention 3 actions")
        XCTAssertTrue(plan.summary.contains("low"), "Summary should mention low risk count")
    }

    func testPlannerAgentSummaryEmpty() async {
        let planner = PlannerAgent()
        let plan = await planner.makePlan(sessionID: "s", recommendations: [], filesByID: [:])
        XCTAssertTrue(plan.summary.contains("No cleanup"), "Empty plan should say no cleanup actions")
        XCTAssertEqual(plan.actions.count, 0)
    }

    // MARK: - DuplicateDetector: Edge Cases (SP-08)

    func testDuplicateDetectorHandlesEmptyFileList() async throws {
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(files: [], sessionID: "scan")
        XCTAssertTrue(analysis.findings.isEmpty)
        XCTAssertTrue(analysis.recommendations.isEmpty)
        XCTAssertTrue(analysis.edges.isEmpty)
    }

    func testDuplicateDetectorHandlesSingleFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("unique".utf8).write(to: root.appendingPathComponent("single.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(files: records, sessionID: "scan")
        XCTAssertTrue(analysis.findings.isEmpty, "Single file should not produce duplicates")
    }

    // MARK: - FileCrawler: Permission Handling (SP-03)

    func testFileCrawlerReportsErrorCount() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("content".utf8).write(to: root.appendingPathComponent("file.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, errors) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        XCTAssertGreaterThan(records.count, 0, "Should find files")
        XCTAssertEqual(errors, 0, "No errors expected for accessible directory")
    }

    func testFileCrawlerHandlesMultipleRoots() async throws {
        let root1 = try makeTemporaryDirectory()
        let root2 = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root1)
            try? FileManager.default.removeItem(at: root2)
        }
        try Data("content1".utf8).write(to: root1.appendingPathComponent("file1.txt", isDirectory: false))
        try Data("content2".utf8).write(to: root2.appendingPathComponent("file2.txt", isDirectory: false))

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root1, root2], sessionID: "scan")
        let names = records.map(\.fileName)
        XCTAssertTrue(names.contains("file1.txt"), "Should find file in root1")
        XCTAssertTrue(names.contains("file2.txt"), "Should find file in root2")
    }

    // MARK: - KeychainStore: Error Handling (PS-03)

    func testKeychainStoreDeleteNonexistentKey() async throws {
        let store = KeychainStore(inMemory: true)
        let account = "nonexistent-\(UUID().uuidString)"
        // Deleting a key that doesn't exist should not throw
        try await store.deleteAPIKey(account: account)
    }

    func testKeychainStoreLoadNonexistentKey() async throws {
        let store = KeychainStore(inMemory: true)
        let account = "nonexistent-\(UUID().uuidString)"
        let key = try await store.loadAPIKey(account: account)
        XCTAssertNil(key, "Loading nonexistent key should return nil")
    }

    // MARK: - ReportGenerator (RP-01, RP-02)

    func testReportGeneratorCreatesPDF() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 1000).write(to: root.appendingPathComponent("test.txt", isDirectory: false))

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: store, planner: planner, memory: memory)
        let (outcome, plan) = try await orchestrator.scan(
            mode: .selectedFolders, selectedFolders: [root],
            providerSettings: ProviderSettings(), includeAI: false, posture: .balanced
        )

        let reportGen = ReportGenerator(store: store)
        let reportURL = try await reportGen.generateCleanupReport(outcome: outcome, plan: plan, destination: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path), "PDF report should be created")
        let attrs = try FileManager.default.attributesOfItem(atPath: reportURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "PDF should have non-zero size")
    }

    // MARK: - Menu Bar: Underlying Logic (MB-03 through MB-07)

    func testMenuBarStorageOverviewLogic() async throws {
        // Storage Overview shows the dashboard with storage info
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("storage-test.sqlite"))

        // Create some snapshots for storage overview
        for i in 0..<5 {
            let snapshot = StorageSnapshot(
                id: "snap-\(i)",
                createdAt: Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date(),
                totalBytes: Int64(500_000_000_000 + i * 1_000_000_000),
                bytesByCategory: [:],
                bytesByRootPath: [:],
                bytesByProject: [:],
                removedBytesThroughApp: 0
            )
            try await store.saveStorageSnapshot(snapshot)
        }

        let snapshots = try await store.recentSnapshots(limit: 30)
        XCTAssertFalse(snapshots.isEmpty, "Storage overview should have snapshots to display")
    }

    func testMenuBarStorageOverviewRequiresSnapshots() async throws {
        // Storage Overview shows storage info from snapshots
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("overview-test.sqlite"))

        // With no snapshots, storage overview should show empty state
        let snapshots = try await store.recentSnapshots(limit: 30)
        XCTAssertTrue(snapshots.isEmpty, "Empty store should have no snapshots")
    }

    // MARK: - Sidebar: Remaining Controls (SB-04 through SB-06)

    func testSidebarBYOKToggleLogic() {
        // BYOK AI toggle binds to includeAI
        let defaults = UserDefaults.standard
        let key = "test_includeAI_\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: key) }

        defaults.set(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key), "BYOK toggle should persist true")
        defaults.set(false, forKey: key)
        XCTAssertFalse(defaults.bool(forKey: key), "BYOK toggle should persist false")
    }

    // MARK: - Onboarding: Remaining Stories (ON-08 through ON-10)

    func testOnboardingAPIBaseURLPersistence() {
        let defaults = UserDefaults.standard
        let key = "test_apiBaseURL_\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: key) }

        let testURL = "https://custom-api.example.com/v1"
        defaults.set(testURL, forKey: key)
        XCTAssertEqual(defaults.string(forKey: key), testURL, "API base URL should persist")
        let url = defaults.string(forKey: key).flatMap(URL.init)
        XCTAssertNotNil(url, "Stored URL should be parseable")
        XCTAssertEqual(url?.host, "custom-api.example.com")
    }

    func testOnboardingTextModelPersistence() {
        let defaults = UserDefaults.standard
        let key = "test_textModel_\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: key) }

        let testModel = "gpt-4-turbo-preview"
        defaults.set(testModel, forKey: key)
        XCTAssertEqual(defaults.string(forKey: key), testModel, "Text model should persist")
    }

    // MARK: - Action Execution: Confirmation Dialog (EX-02)

    // MARK: - Action Execution: Confirmation Dialog (EX-02)
    // The dialog-count test was removed: it set userDecision on a local plan
    // copy and asserted the values it had just set. Actual approval flow is
    // covered by AppViewModelTests (testApproveRejectAlwaysNeverUpdatePlanState)
    // and ReviewFlowLogicTests.

    // MARK: - Action Execution: Progress Tracking (EX-11)
    // AppViewModel execution-state tracking (isExecuting, executionProgress,
    // executionTotalActions, executionSummary, plan status transitions) is covered
    // by AppViewModelTests (testExecuteSafeActionsRunsOnlyLowRisk,
    // testExecuteApprovedTagActionAndUndoRestoresTags, testNewScanResetsExecutionState).

    // MARK: - Undo System: Batch Restore with Failures (UN-01)

    func testUndoManagerServiceBatchRestorePartialFailure() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let undoService = UndoManagerService(store: store, memory: memory)
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var undoRecords: [UndoRecord] = []

        // Create one valid undo record
        let file = root.appendingPathComponent("valid.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)
        let trashURL = try FixtureTrash().trashItem(at: file)

        let logID = UUID().uuidString
        let log = OperationLog(
            id: logID, plannedActionID: "p1", operationType: .moveToTrash,
            beforeState: ["path": file.path, "file_id": "file-1"],
            afterState: ["trash_path": trashURL?.path ?? ""],
            executorVersion: "1.0", result: "moved_to_trash", error: nil, timestamp: Date()
        )
        try await store.saveOperationLog(log)

        let validUndo = UndoRecord(
            id: UUID().uuidString, operationLogID: logID, inverseAction: .restore,
            restoreURL: file, trashURL: trashURL,
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            status: .available
        )
        try await store.saveUndoRecord(validUndo)
        undoRecords.append(validUndo)

        // Create one expired undo record (will fail)
        let expiredUndo = UndoRecord(
            id: UUID().uuidString, operationLogID: "log-expired", inverseAction: .restore,
            restoreURL: URL(fileURLWithPath: "/tmp/expired.txt"), trashURL: nil,
            validUntil: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            status: .available
        )
        try await store.saveUndoRecord(expiredUndo)
        undoRecords.append(expiredUndo)

        let (restored, failureCount) = await undoService.restoreBatch(undoRecords)
        XCTAssertEqual(restored.count, 1, "Only valid undo should be restored")
        XCTAssertEqual(failureCount, 1, "Expired undo should count as failure")
    }

    // MARK: - Plan Status Transitions (M-06)

    // MARK: - Calibration Presets (ST-13 through ST-17)

    func testCalibrationPresets() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("cal-presets.sqlite"))
        let memory = MemoryEngine(store: store)

        let presets = [
            "Too aggressive on code files",
            "Too conservative on downloads",
            "Never suggest deleting design source",
            "Prefer archive over delete",
            "Ask before touching cloud files"
        ]

        for preset in presets {
            try await memory.applyCalibrationPreference(preset)
        }

        let rules = try await store.loadMemoryRules()
        XCTAssertEqual(rules.count, presets.count, "Each preset should create a rule")
    }

    // MARK: - Organization Suggestions: Tag Actions (SP-25)

    func testOrganizationPlannerSuggestsTagForDownloads() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let file = downloads.appendingPathComponent("photo.jpg", isDirectory: false)
        try Data(repeating: 0, count: 1000).write(to: file)
        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let planner = OrganizationPlanner()
        let (_, recs) = await planner.suggestOrganization(files: records, sessionID: "scan")
        let tagRecs = recs.filter { $0.actionType == .tag }
        XCTAssertFalse(tagRecs.isEmpty, "Old files in Downloads should get tag recommendations")
    }

    // MARK: - ContentExtractor: Language Detection (SP-11)

    // MARK: - FingerprintService: Perceptual Hash (SP-09)

    func testFingerprintServicePerceptualHashForNonImage() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("text.txt", isDirectory: false)
        try Data("not an image".utf8).write(to: file)

        let hash = await FingerprintService.perceptualHash(for: file)
        XCTAssertNil(hash, "Non-image file should return nil perceptual hash")
    }

    // MARK: - FingerprintService: Video Hash (SP-10)
    // videoKeyframeHash was removed in the performance pass: its output was
    // written to fingerprints but never read by any grouping logic, so every
    // scan paid AVAssetReader + CIContext cost per video for zero benefit.

    // MARK: - PathSafetyPolicy: Cloud Provider Detection (PS-10)
    // All cloud providers are covered by testPathSafetyPolicyCloudProviderDetection
    // above; the per-provider variants were duplicates of it and were removed.

    // MARK: - SQLiteStore: Plan Persistence (DP-01)

    func testSQLiteStorePersistsPlanWithActions() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("plan-test.sqlite"))

        let action = PlannedAction(
            id: "a1", planID: "p1", actionType: .moveToTrash, targets: ["f1"],
            destination: nil, status: .proposed, risk: .low, confidence: 0.9,
            reason: "test", userDecision: .undecided, executedAt: nil, findingID: nil
        )
        let plan = Plan(
            id: "p1", scanSessionID: "s1", createdAt: Date(), status: .proposed,
            summary: "Test plan", estimatedReclaimableBytes: 1000, estimatedFilesAffected: 1,
            riskBreakdown: [.low: 1], actions: [action]
        )
        try await store.savePlan(plan)

        let loaded = try await store.loadPlan(id: "p1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.actions.count, 1)
        XCTAssertEqual(loaded?.actions.first?.actionType, .moveToTrash)
    }

    // MARK: - SQLiteStore: Recent Plans (DP-02)

    func testSQLiteStoreRecentPlans() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("recent-test.sqlite"))

        for i in 0..<3 {
            let plan = Plan(
                id: "plan-\(i)", scanSessionID: "s\(i)", createdAt: Date(),
                status: .completed, summary: "Plan \(i)",
                estimatedReclaimableBytes: Int64(i * 1000), estimatedFilesAffected: i,
                riskBreakdown: [:], actions: []
            )
            try await store.savePlan(plan)
        }

        let recent = try await store.recentPlans(limit: 10)
        XCTAssertGreaterThanOrEqual(recent.count, 3, "Should load recent plans")
    }

    // MARK: - SQLiteStore: Snapshot Comparison (DP-03)

    func testSQLiteStoreSnapshotComparison() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("comparison-test.sqlite"))

        let snapshot1 = StorageSnapshot(
            id: "old", createdAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            totalBytes: 400_000_000_000, bytesByCategory: [.cache: 50_000_000_000],
            bytesByRootPath: [:], bytesByProject: [:], removedBytesThroughApp: 0
        )
        let snapshot2 = StorageSnapshot(
            id: "new", createdAt: Date(),
            totalBytes: 450_000_000_000, bytesByCategory: [.cache: 60_000_000_000],
            bytesByRootPath: [:], bytesByProject: [:], removedBytesThroughApp: 10_000_000_000
        )
        try await store.saveStorageSnapshot(snapshot1)
        try await store.saveStorageSnapshot(snapshot2)

        let comparison = try await store.snapshotComparison()
        XCTAssertNotNil(comparison, "Should be able to compare snapshots")
    }

    // MARK: - ActionExecutor: Operation Logs (EX-13)

    func testActionExecutorCreatesOperationLogs() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("log-test.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        let action = PlannedAction(
            id: "log-1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9,
            reason: "test logging", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertFalse(summary.logs.isEmpty, "Should create operation logs")
        XCTAssertEqual(summary.logs.first?.operationType, .moveToTrash)
    }

    // MARK: - Action Execution: Undo Records Created (EX-14)

    func testActionExecutorCreatesUndoRecords() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("undo-test.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let record = records.first { $0.url == file.standardizedFileURL }!

        let store = try SQLiteStore.inMemory()
        let auditor = SafetyAuditor()
        let executor = TestFixtures.makeExecutor(store: store, auditor: auditor)

        let action = PlannedAction(
            id: "undo-1", planID: "p1", actionType: .moveToTrash, targets: [record.id],
            destination: nil, status: .approved, risk: .low, confidence: 0.9,
            reason: "test undo creation", userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [record.id: record])
        XCTAssertFalse(summary.undoRecords.isEmpty, "Should create undo records")
        XCTAssertEqual(summary.undoRecords.first?.inverseAction, .restore)
        XCTAssertEqual(summary.undoRecords.first?.status, .available)
    }
    // MARK: - PathSafetyPolicy: SIP Path Protection (PS-04)

    func testPathSafetyPolicyProtectsSIPPaths() {
        let policy = PathSafetyPolicy()
        let sipPaths = [
            "/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/libexec",
            "/usr/lib", "/usr/share", "/etc", "/private/etc", "/tmp", "/private/tmp"
        ]
        for path in sipPaths {
            let url = URL(fileURLWithPath: path + "/test")
            let flags = policy.riskFlags(for: url, isDirectory: false)
            XCTAssertTrue(flags.contains(.sipProtectedSystemPath), "\(path) should be SIP-protected")
        }
    }

    func testDeepSystemPathsAreNotTraversalSkipped() {
        // The deep-system / macOS-system-caches sections legitimately enumerate
        // these trees as inspect-only targets; the SIP list must not block them.
        let policy = PathSafetyPolicy()
        for path in ["/Library/Caches", "/Library/Logs", "/Library/Updates"] {
            XCTAssertFalse(policy.shouldSkipTraversal(of: URL(fileURLWithPath: path)), "\(path) must remain scannable")
        }
    }

    // MARK: - PathSafetyPolicy: Protected Directories (PS-04)

    func testPathSafetyPolicyProtectsSensitiveDirectories() {
        let policy = PathSafetyPolicy()
        let protectedDirs = [".ssh", ".gnupg", ".aws", "Keychains", "MobileSync", "Mail"]
        for dir in protectedDirs {
            let url = URL(fileURLWithPath: "/Users/me/\(dir)/file")
            XCTAssertTrue(policy.isProtectedFromCleanup(url: url, isDirectory: false), "\(dir) should be protected")
        }
    }

    // MARK: - PathSafetyPolicy: Protected Files (PS-05)

    func testPathSafetyPolicyProtectsSensitiveFiles() {
        let policy = PathSafetyPolicy()
        let protectedFiles = [".env", ".env.local", "id_rsa", "id_ed25519", "known_hosts"]
        for file in protectedFiles {
            let url = URL(fileURLWithPath: "/Users/me/project/\(file)")
            XCTAssertTrue(policy.isProtectedFromCleanup(url: url, isDirectory: false), "\(file) should be protected")
        }
    }

    // MARK: - PathSafetyPolicy: Protected Extensions (PS-05)

    func testPathSafetyPolicyProtectsCertificateExtensions() {
        let policy = PathSafetyPolicy()
        let protectedExts = ["pem", "key", "p12", "pfx", "cer", "crt", "gpg", "pgp"]
        for ext in protectedExts {
            let url = URL(fileURLWithPath: "/Users/me/cert.\(ext)")
            XCTAssertTrue(policy.isProtectedFromCleanup(url: url, isDirectory: false), ".\(ext) should be protected")
        }
    }

    // MARK: - MemoryEngine: Always Rule Boosts Confidence (ML-01)

    func testMemoryEngineAlwaysRuleBoostsConfidence() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)

        try await memory.applyCalibrationPreference("Always consider moveToTrash for all files", scopeType: "global", scopeValue: "")

        let file = makeFileRecord(id: "f1", path: "/tmp/test.txt", sizeBytes: 100)
        let rec = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.7)
        let adjusted = try await memory.applyMemory(to: [rec], filesByID: [file.id: file])
        XCTAssertEqual(adjusted.first?.confidence ?? 0, 0.85, accuracy: 0.01, "Always rule should boost confidence by 0.15")
    }

    // MARK: - MemoryEngine: Never Rule Downgrades (ML-02)

    func testMemoryEngineNeverRuleDowngradesAction() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)

        try await memory.applyCalibrationPreference("Never suggest moveToTrash in this directory", scopeType: "global", scopeValue: "")

        let file = makeFileRecord(id: "f1", path: "/tmp/test.txt", sizeBytes: 100)
        let rec = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        let adjusted = try await memory.applyMemory(to: [rec], filesByID: [file.id: file])
        XCTAssertEqual(adjusted.first?.confidence, 0.55, "Never rule should cap confidence at 0.55")
        XCTAssertEqual(adjusted.first?.actionType, .inspectOnly, "Never rule should change moveToTrash to inspectOnly")
    }

    // MARK: - MemoryEngine: Prefer Archive Rule (ML-05)

    func testMemoryEnginePreferArchiveRule() async throws {
        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)

        try await memory.applyCalibrationPreference("Prefer archive over delete for all files", scopeType: "global", scopeValue: "")

        let file = makeFileRecord(id: "f1", path: "/tmp/test.txt", sizeBytes: 100)
        let rec = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        let adjusted = try await memory.applyMemory(to: [rec], filesByID: [file.id: file])
        XCTAssertEqual(adjusted.first?.actionType, .archive, "Prefer archive rule should change action to archive")
    }
    // MARK: - ActionExecutor: Archive Partial-Failure Handling (EX-05)

    func testActionExecutorArchiveContinuesAfterOneTargetFails() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let goodFile = root.appendingPathComponent("good.txt", isDirectory: false)
        try Data("good".utf8).write(to: goodFile)
        // "missing.txt" referenced by the action but never created on disk — ditto will fail for it.
        let destination = root.appendingPathComponent("Archive", isDirectory: true)

        let crawler = FileCrawler()
        let (records, _) = await crawler.crawl(rootURLs: [root], sessionID: "scan")
        let goodRecord = try XCTUnwrap(records.first { $0.url == goodFile.standardizedFileURL })
        // Fabricate a record for a non-existent file so the executor attempts to archive it.
        let missingRecord = FileRecord(
            scanSessionID: "scan", url: root.appendingPathComponent("missing.txt", isDirectory: false),
            kind: .regularFile, sizeBytes: 10
        )
        let filesByID = [goodRecord.id: goodRecord, missingRecord.id: missingRecord]
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("archive-partial.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)

        let action = PlannedAction(
            id: "archive-partial", planID: "plan", actionType: .archive,
            targets: [missingRecord.id, goodRecord.id], destination: destination,
            status: .approved, risk: .medium, confidence: 1, reason: "test partial archive",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: filesByID)

        // The good file should still be archived and trashed despite the missing target failing.
        XCTAssertFalse(FileManager.default.fileExists(atPath: goodFile.path), "Good file should have been archived and trashed")
        XCTAssertFalse(summary.failures.isEmpty, "A failure should be recorded for the missing target")
        // One log for the successful archive, zero for the failed one.
        XCTAssertEqual(summary.logs.count, 1, "Only the successful archive should produce a log")
    }

    // MARK: - ActionExecutor: Package Cleanup Partial-Failure Handling (EX-10)

    func testActionExecutorPackageCleanupContinuesAfterOneCandidateFails() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("pkg-partial.sqlite", isDirectory: false))
        let executor = TestFixtures.makeExecutor(store: store)
        // A candidate that always fails (exit 1).
        let failingCandidate = PackageCleanupCandidate(
            id: "fail", title: "Failing", commandPath: URL(fileURLWithPath: "/bin/false"),
            arguments: [], dryRunOutput: "", risk: .low, category: .packageManagerCleanup
        )
        // A candidate that succeeds (exit 0) and writes a marker.
        let marker = root.appendingPathComponent("ran.txt", isDirectory: false)
        let okCandidate = PackageCleanupCandidate(
            id: "ok", title: "OK", commandPath: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo done > '\(marker.path)'"], dryRunOutput: "", risk: .low, category: .packageManagerCleanup
        )
        let action = PlannedAction(
            id: "pkg-partial", planID: "plan", actionType: .runPackageManagerCleanup,
            targets: [failingCandidate.id, okCandidate.id], destination: nil,
            status: .approved, risk: .low, confidence: 0.8, reason: "test partial pkg",
            userDecision: .approved, executedAt: nil, findingID: nil
        )
        let summary = await executor.execute(actions: [action], filesByID: [:], packageCandidates: [failingCandidate, okCandidate])

        XCTAssertEqual(summary.logs.count, 1, "Only the successful candidate should produce a log")
        XCTAssertFalse(summary.failures.isEmpty, "A failure should be recorded for the failing candidate")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "Successful candidate should still have run despite the earlier failure")
    }
}
