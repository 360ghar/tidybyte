import Foundation
@testable import MacOSCleanerCore
import XCTest

/// PlannerAgent tests, split out of the former MacOSCleanerTests god file.
final class PlannerAgentServiceTests: XCTestCase {

    func testPlannerAgentCapsAIConfidenceAt085() async {
        let planner = PlannerAgent()
        let record = FileRecord(scanSessionID: "scan", url: URL(fileURLWithPath: "/tmp/test"), sizeBytes: 100)
        let filesByID = [record.id: record]

        let aiPayload = AIRecommendationPayload(
            category: .cache, action: .moveToTrash, targetFileID: record.id,
            confidence: 0.99, risk: .low, reason: "AI suggestion"
        )
        let plan = await planner.makePlan(
            sessionID: "scan", recommendations: [],
            filesByID: filesByID, aiRecommendations: [aiPayload]
        )
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.confidence, 0.85)
    }

    func testPlannerAgentDeduplicatesActions() async {
        let planner = PlannerAgent()
        let record = FileRecord(scanSessionID: "scan", url: URL(fileURLWithPath: "/tmp/test"), sizeBytes: 100)
        let filesByID = [record.id: record]

        // Two recommendations with the SAME findingID should be deduplicated
        let rec1 = Recommendation(
            id: "r1", findingID: "f1", actionType: .moveToTrash,
            targetFileIDs: [record.id], confidence: 0.9, risk: .low,
            reason: "first", expectedBytesReclaimed: 100,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let rec2 = Recommendation(
            id: "r2", findingID: "f1", actionType: .moveToTrash,
            targetFileIDs: [record.id], confidence: 0.8, risk: .low,
            reason: "duplicate", expectedBytesReclaimed: 100,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let plan = await planner.makePlan(
            sessionID: "scan", recommendations: [rec1, rec2],
            filesByID: filesByID
        )
        XCTAssertEqual(plan.actions.count, 1, "Same findingID + same action + same targets = deduplicated")
        XCTAssertEqual(plan.actions.first?.confidence, 0.9)

        // Two recommendations with DIFFERENT findingIDs should be kept (cross-category preservation)
        let rec3 = Recommendation(
            id: "r3", findingID: "f1", actionType: .moveToTrash,
            targetFileIDs: [record.id], confidence: 0.9, risk: .low,
            reason: "from finding 1", expectedBytesReclaimed: 100,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let rec4 = Recommendation(
            id: "r4", findingID: "f2", actionType: .moveToTrash,
            targetFileIDs: [record.id], confidence: 0.8, risk: .low,
            reason: "from finding 2", expectedBytesReclaimed: 100,
            requiresConfirmation: true, llmTraceID: nil, policyTraceID: nil
        )
        let plan2 = await planner.makePlan(
            sessionID: "scan", recommendations: [rec3, rec4],
            filesByID: filesByID
        )
        XCTAssertEqual(plan2.actions.count, 2, "Different findingIDs = kept as separate actions")
    }

    func testPlannerAgentNaturalLanguageFilterArchive() async {
        let planner = PlannerAgent()
        let record = FileRecord(scanSessionID: "scan", url: URL(fileURLWithPath: "/tmp/test"), sizeBytes: 100)
        let filesByID = [record.id: record]

        let plan = Plan(
            id: "plan", scanSessionID: "scan", createdAt: Date(),
            status: .proposed, summary: "test", estimatedReclaimableBytes: 100,
            estimatedFilesAffected: 1, riskBreakdown: [.low: 1],
            actions: [
                PlannedAction(
                    id: "a1", planID: "plan", actionType: .tag,
                    targets: [record.id], destination: nil, status: .proposed,
                    risk: .low, confidence: 0.8, reason: "tag it",
                    userDecision: .undecided, executedAt: nil, findingID: nil
                )
            ]
        )

        let updated = await planner.planForNaturalLanguageCommand("archive this", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(updated.actions.first?.actionType, .archive)
        XCTAssertNotNil(updated.originalActions)
    }


    func testPlannerAgentNaturalLanguageDeleteCommand() async {
        let planner = PlannerAgent()
        let record = FileRecord(scanSessionID: "scan", url: URL(fileURLWithPath: "/tmp/delete-me.txt"), sizeBytes: 100)
        let filesByID = [record.id: record]

        let plan = Plan(
            id: "plan", scanSessionID: "scan", createdAt: Date(),
            status: .proposed, summary: "test", estimatedReclaimableBytes: 100,
            estimatedFilesAffected: 1, riskBreakdown: [.low: 1],
            actions: [
                PlannedAction(
                    id: "a1", planID: "plan", actionType: .tag,
                    targets: [record.id], destination: nil, status: .proposed,
                    risk: .low, confidence: 0.8, reason: "tag it",
                    userDecision: .undecided, executedAt: nil, findingID: nil
                )
            ]
        )

        let updated = await planner.planForNaturalLanguageCommand("delete this", existingPlan: plan, filesByID: filesByID)
        XCTAssertEqual(updated.actions.first?.actionType, .moveToTrash)
    }

    func testPlannerAgentNaturalLanguageSafeCommand() async {
        let planner = PlannerAgent()
        let record = FileRecord(scanSessionID: "scan", url: URL(fileURLWithPath: "/tmp/test.txt"), sizeBytes: 100)
        let filesByID = [record.id: record]

        let plan = Plan(
            id: "plan", scanSessionID: "scan", createdAt: Date(),
            status: .proposed, summary: "test", estimatedReclaimableBytes: 100,
            estimatedFilesAffected: 1, riskBreakdown: [.low: 1, .medium: 1],
            actions: [
                PlannedAction(
                    id: "a1", planID: "plan", actionType: .moveToTrash,
                    targets: [record.id], destination: nil, status: .proposed,
                    risk: .low, confidence: 0.8, reason: "test",
                    userDecision: .undecided, executedAt: nil, findingID: nil
                ),
                PlannedAction(
                    id: "a2", planID: "plan", actionType: .moveToTrash,
                    targets: [record.id], destination: nil, status: .proposed,
                    risk: .medium, confidence: 0.7, reason: "test medium",
                    userDecision: .undecided, executedAt: nil, findingID: nil
                )
            ]
        )

        let updated = await planner.planForNaturalLanguageCommand("be safe", existingPlan: plan, filesByID: filesByID)
        // Safe mode should filter to only low-risk actions
        XCTAssertEqual(updated.actions.count, 1)
        XCTAssertEqual(updated.actions.first?.risk, .low)
    }


    func testPlannerAgentDedupMergesSameActionSameTargets() async {
        let planner = PlannerAgent()
        // Both recommendations share the same findingID — should be deduplicated
        var rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.8)
        rec1.findingID = "shared-finding"
        var rec2 = makeRecommendation(id: "r2", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.9)
        rec2.findingID = "shared-finding"
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: [:])
        XCTAssertEqual(plan.actions.count, 1, "Same findingID + same action + same targets = merged")
    }

    func testPlannerAgentKeepsDifferentActionsForSameTarget() async {
        let planner = PlannerAgent()
        let rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.8)
        let rec2 = makeRecommendation(id: "r2", targetID: "f1", action: .archive, risk: .low, confidence: 0.8)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: [:])
        XCTAssertEqual(plan.actions.count, 2, "Different action types for same target should both be kept")
    }

    func testPlannerAgentFiltersLowConfidence() async {
        let planner = PlannerAgent()
        let rec1 = makeRecommendation(id: "r1", targetID: "f1", action: .moveToTrash, risk: .low, confidence: 0.39)
        let rec2 = makeRecommendation(id: "r2", targetID: "f2", action: .moveToTrash, risk: .low, confidence: 0.41)
        let plan = await planner.makePlan(sessionID: "s", recommendations: [rec1, rec2], filesByID: [:])
        XCTAssertEqual(plan.actions.count, 1, "Recommendation below 0.40 confidence should be filtered")
        XCTAssertEqual(plan.actions.first?.targets.first, "f2")
    }

    func makeTemporaryDirectory() throws -> URL {
        try TestFixtures.makeTemporaryDirectory()
    }

    private func makeRecommendation(id: String, targetID: String, action: ActionType, risk: RiskLevel, confidence: Double = 0.8) -> Recommendation {
        TestFixtures.makeRecommendation(id: id, targetID: targetID, action: action, risk: risk, confidence: confidence)
    }
}
