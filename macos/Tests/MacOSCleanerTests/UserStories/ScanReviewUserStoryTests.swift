import Foundation
@testable import MacOSCleanerCore
import XCTest

private actor ScanProgressCollector {
    private(set) var updates: [ScanOrchestrator.ScanProgress] = []

    func append(_ update: ScanOrchestrator.ScanProgress) {
        updates.append(update)
    }

    func snapshot() -> [ScanOrchestrator.ScanProgress] {
        updates
    }
}

final class ScanReviewUserStoryTests: XCTestCase {
    func testSelectedFolderScanProducesReviewableCleanupPlanAcrossCoreCategories() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "ScanReview")
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try UserStoryFixtures.writeFile("Project/package.json", in: root, data: Data("{}".utf8))
        _ = try UserStoryFixtures.writeFile("Project/node_modules/package.bin", in: root, data: Data(repeating: 1, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile("Caches/App/cache.bin", in: root, data: Data(repeating: 2, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile("Downloads/duplicate-a.txt", in: root, data: Data("same-payload".utf8))
        _ = try UserStoryFixtures.writeFile("Downloads/duplicate-b.txt", in: root, data: Data("same-payload".utf8))
        _ = try UserStoryFixtures.writeFile("Downloads/old-installer.dmg", in: root, data: Data("installer".utf8), modifiedDaysAgo: 45)
        _ = try UserStoryFixtures.writeFile("Tidybyte Inbox/loose.pdf", in: root, data: Data("%PDF".utf8), modifiedDaysAgo: 14)

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let orchestrator = ScanOrchestrator(store: store, memory: memory)

        let (outcome, plan) = try await orchestrator.scan(
            mode: .selectedFolders,
            selectedFolders: [root],
            providerSettings: ProviderSettings(privacyMode: .metadataOnlyAI),
            includeAI: false,
            posture: .conservative
        )

        XCTAssertEqual(outcome.session.status, .completed)
        XCTAssertGreaterThanOrEqual(outcome.files.count, 8)
        XCTAssertTrue(outcome.findings.contains { $0.category == .cache })
        XCTAssertTrue(outcome.findings.contains { $0.category == .duplicate })
        XCTAssertTrue(outcome.findings.contains { $0.category == .developerArtifact })
        XCTAssertTrue(outcome.findings.contains { $0.category == .oldInstaller })
        XCTAssertTrue(outcome.findings.contains { $0.category == .organization })
        XCTAssertTrue(outcome.projects.contains { $0.projectType == "Node" })
        XCTAssertTrue(outcome.edges.contains { $0.edgeType == .sameProject || $0.edgeType == .manifestOf })
        XCTAssertFalse(outcome.packageCandidates.contains { $0.category == .packageManagerCleanup })
        XCTAssertFalse(plan.actions.contains { $0.actionType == .runPackageManagerCleanup })
        XCTAssertGreaterThan(plan.estimatedReclaimableBytes, 0)
        XCTAssertGreaterThan(plan.estimatedFilesAffected, 0)
        XCTAssertTrue(plan.actions.allSatisfy { $0.userDecision == .undecided && $0.status == .proposed })
    }

    func testSafeReviewPlanNeverAutoApprovesOrExecutesHighRiskDestructiveWork() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "SafeReview")
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = try UserStoryFixtures.writeFile("Caches/App/cache.bin", in: root, data: Data(repeating: 1, count: 2_000_000))
        let secretURL = try UserStoryFixtures.writeFile(".env", in: root, data: Data("TOKEN=secret".utf8))
        let cacheRecord = try await UserStoryFixtures.fileRecord(from: cacheURL, sessionID: "scan")
        let secretRecord = try await UserStoryFixtures.fileRecord(from: secretURL, sessionID: "scan")
        let filesByID = [cacheRecord.id: cacheRecord, secretRecord.id: secretRecord]
        let planner = PlannerAgent()
        let plan = Plan(
            id: "review-plan",
            scanSessionID: "scan",
            createdAt: Date(),
            status: .proposed,
            summary: "review",
            estimatedReclaimableBytes: cacheRecord.sizeBytes + secretRecord.sizeBytes,
            estimatedFilesAffected: 2,
            riskBreakdown: [.low: 1, .high: 1],
            actions: [
                PlannedAction(
                    id: "cache-action",
                    planID: "review-plan",
                    actionType: .moveToTrash,
                    targets: [cacheRecord.id],
                    destination: nil,
                    status: .proposed,
                    risk: .low,
                    confidence: 0.9,
                    reason: "cache",
                    userDecision: .undecided,
                    executedAt: nil,
                    findingID: nil
                ),
                PlannedAction(
                    id: "secret-action",
                    planID: "review-plan",
                    actionType: .moveToTrash,
                    targets: [secretRecord.id],
                    destination: nil,
                    status: .proposed,
                    risk: .high,
                    confidence: 0.4,
                    reason: "secret",
                    userDecision: .undecided,
                    executedAt: nil,
                    findingID: nil
                )
            ]
        )

        let safePlan = await planner.planForNaturalLanguageCommand("safe", existingPlan: plan, filesByID: filesByID)

        XCTAssertEqual(safePlan.actions.map(\.id), ["cache-action"])
        XCTAssertEqual(safePlan.estimatedFilesAffected, 1)
        XCTAssertEqual(safePlan.riskBreakdown, [.low: 1])
        XCTAssertTrue(safePlan.actions.allSatisfy { $0.userDecision == .undecided && $0.status == .proposed })
    }

    func testScanProgressEmitsCanonical5StepHeaderSequence() async throws {
        let root = try UserStoryFixtures.makeTemporaryDirectory(named: "ScanProgress")
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try UserStoryFixtures.writeFile("Downloads/sample.log", in: root, data: Data(repeating: 1, count: 1024))
        _ = try UserStoryFixtures.writeFile("Projects/app.txt", in: root, data: Data("fixture".utf8))

        let store = try SQLiteStore(databaseURL: root.appendingPathComponent("scan-progress.sqlite", isDirectory: false))
        let memory = MemoryEngine(store: store)
        let orchestrator = ScanOrchestrator(store: store, memory: memory)
        let collector = ScanProgressCollector()

        _ = try await orchestrator.scan(
            mode: .selectedFolders,
            selectedFolders: [root],
            providerSettings: ProviderSettings(privacyMode: .metadataOnlyAI),
            includeAI: false,
            posture: .conservative,
            progress: { progress in
                await collector.append(progress)
            }
        )

        let updates = await collector.snapshot()
        XCTAssertFalse(updates.isEmpty, "Scan should emit progress updates.")
        XCTAssertEqual(updates.first?.totalSteps, 5, "Scan should use five progress stages for header display.")
        let steps = updates.map(\.currentStep)
        XCTAssertEqual(steps.first, 1, "Scan should start at step 1.")
        XCTAssertEqual(steps.last, 5, "Scan should finish at step 5.")
        XCTAssertGreaterThanOrEqual(steps.count, 4, "Scan should emit core progress stages plus completion stage.")
        XCTAssertTrue(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 }, "Progress steps should be nondecreasing.")
        XCTAssertEqual(Set(updates.map(\.totalSteps)).count, 1, "Total step count should stay consistent.")
    }
}
