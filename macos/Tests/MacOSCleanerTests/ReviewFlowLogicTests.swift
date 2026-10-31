import Foundation
import XCTest
@testable import MacOSCleanerAppKit
@testable import MacOSCleanerCore

/// Unit tests for the pure review-flow helpers in `AppViewModel+Review.swift`
/// (matchingActions(filter:in:), visibleUndecidedCount(actions:filter:),
/// actionsToApprove(actions:filter:), undecidedActions(in:),
/// lowRiskUndecidedActions(in:), suggestionCommands).
@MainActor
final class ReviewFlowLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func makeAction(
        id: String,
        risk: RiskLevel,
        decision: UserDecision,
        confidence: Double = 0.9
    ) -> PlannedAction {
        PlannedAction(
            id: id,
            planID: "plan-test",
            actionType: .moveToTrash,
            targets: ["file-\(id)"],
            destination: nil,
            status: .proposed,
            risk: risk,
            confidence: confidence,
            reason: "Test action \(id)",
            userDecision: decision,
            executedAt: nil,
            findingID: nil
        )
    }

    /// The G-01 reproduction shape: 8 actions (5 low + 2 medium + 1 high),
    /// all undecided.
    private func makeEightUndecidedActions() -> [PlannedAction] {
        var actions: [PlannedAction] = []
        for index in 0..<5 {
            actions.append(makeAction(id: "low-\(index)", risk: .low, decision: .undecided))
        }
        for index in 0..<2 {
            actions.append(makeAction(id: "medium-\(index)", risk: .medium, decision: .undecided))
        }
        actions.append(makeAction(id: "high-0", risk: .high, decision: .undecided))
        return actions
    }

    // MARK: - visibleUndecidedCount(actions:filter:)

    func testVisibleUndecidedCountWithNoFilterCountsAllUndecided() {
        let actions = makeEightUndecidedActions()
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: actions, filter: nil), 8)
    }

    func testVisibleUndecidedCountRespectsRiskFilter() {
        let actions = makeEightUndecidedActions()
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: actions, filter: .low), 5)
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: actions, filter: .medium), 2)
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: actions, filter: .high), 1)
    }

    func testVisibleUndecidedCountHighFilterExcludesForbidden() {
        let actions = makeEightUndecidedActions()
            + [makeAction(id: "forbidden-0", risk: .forbidden, decision: .undecided)]
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: actions, filter: .high), 1)
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: actions, filter: .forbidden), 1)
    }

    func testVisibleUndecidedCountExcludesDecidedActions() {
        let actions = makeEightUndecidedActions()
        var approved = actions
        approved[0].userDecision = .approved
        approved[1].userDecision = .rejected
        approved[2].userDecision = .alwaysDoThis
        approved[3].userDecision = .neverDoThisHere
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: approved, filter: nil), 4)
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: approved, filter: .low), 1)
    }

    func testVisibleUndecidedCountEmptyActions() {
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: [], filter: nil), 0)
        XCTAssertEqual(AppViewModel.visibleUndecidedCount(actions: [], filter: .high), 0)
    }

    // MARK: - actionsToApprove(actions:filter:)

    func testActionsToApproveMatchesVisibleUndecidedSet() {
        let actions = makeEightUndecidedActions()
        let approveSet = AppViewModel.actionsToApprove(actions: actions, filter: nil)
        XCTAssertEqual(approveSet.count, 8)
        XCTAssertEqual(
            approveSet.map(\.id).sorted(),
            actions.map(\.id).sorted()
        )
    }

    func testActionsToApproveRespectsFilter() {
        let actions = makeEightUndecidedActions()
        XCTAssertEqual(AppViewModel.actionsToApprove(actions: actions, filter: .low).count, 5)
        XCTAssertEqual(AppViewModel.actionsToApprove(actions: actions, filter: .medium).count, 2)
        XCTAssertEqual(AppViewModel.actionsToApprove(actions: actions, filter: .high).count, 1)
        // The approve set must match the visible undecided count exactly.
        XCTAssertEqual(
            AppViewModel.actionsToApprove(actions: actions, filter: .medium).count,
            AppViewModel.visibleUndecidedCount(actions: actions, filter: .medium)
        )
    }

    func testActionsToApproveHighFilterExcludesForbiddenUndecided() {
        let actions = makeEightUndecidedActions()
            + [makeAction(id: "forbidden-0", risk: .forbidden, decision: .undecided)]
        let approveSet = AppViewModel.actionsToApprove(actions: actions, filter: .high)
        XCTAssertEqual(approveSet.count, 1)
        XCTAssertFalse(approveSet.contains { $0.risk == .forbidden })
        XCTAssertEqual(AppViewModel.actionsToApprove(actions: actions, filter: .forbidden).count, 1)
    }

    func testActionsToApproveExcludesDecidedActions() {
        let actions = makeEightUndecidedActions()
        var mixed = actions
        mixed[0].userDecision = .approved
        mixed[1].userDecision = .rejected
        mixed[2].userDecision = .alwaysDoThis
        mixed[3].userDecision = .neverDoThisHere
        let approveSet = AppViewModel.actionsToApprove(actions: mixed, filter: nil)
        XCTAssertEqual(approveSet.count, 4)
        XCTAssertFalse(approveSet.contains { $0.userDecision == .approved })
        XCTAssertFalse(approveSet.contains { $0.userDecision == .rejected })
        XCTAssertFalse(approveSet.contains { $0.userDecision == .alwaysDoThis })
        XCTAssertFalse(approveSet.contains { $0.userDecision == .neverDoThisHere })
        XCTAssertTrue(approveSet.allSatisfy { $0.userDecision == .undecided })
    }

    func testActionsToApproveEmptyActionsReturnsEmpty() {
        XCTAssertTrue(AppViewModel.actionsToApprove(actions: [], filter: nil).isEmpty)
        XCTAssertTrue(AppViewModel.actionsToApprove(actions: [], filter: .high).isEmpty)
    }

    func testActionsToApproveAllDecidedReturnsEmpty() {
        let actions = makeEightUndecidedActions().map { action in
            var decided = action
            decided.userDecision = .approved
            return decided
        }
        XCTAssertTrue(AppViewModel.actionsToApprove(actions: actions, filter: nil).isEmpty)
        XCTAssertTrue(AppViewModel.actionsToApprove(actions: actions, filter: .low).isEmpty)
    }

    func testActionsToApproveIsDeterministic() {
        let actions = makeEightUndecidedActions()
        let first = AppViewModel.actionsToApprove(actions: actions, filter: nil)
        let second = AppViewModel.actionsToApprove(actions: actions, filter: nil)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    // MARK: - undecidedActions(in:)

    func testUndecidedActionsIgnoresRisk() {
        let actions = makeEightUndecidedActions()
            + [makeAction(id: "forbidden-0", risk: .forbidden, decision: .undecided)]
        XCTAssertEqual(AppViewModel.undecidedActions(in: actions).count, 9)
    }

    func testUndecidedActionsExcludesDecided() {
        let actions = makeEightUndecidedActions()
        var mixed = actions
        mixed[0].userDecision = .approved
        mixed[7].userDecision = .neverDoThisHere
        let undecided = AppViewModel.undecidedActions(in: mixed)
        XCTAssertEqual(undecided.count, 6)
        XCTAssertFalse(undecided.contains { $0.id == "low-0" })
        XCTAssertFalse(undecided.contains { $0.id == "high-0" })
    }

    // MARK: - lowRiskUndecidedActions(in:)

    func testLowRiskUndecidedActionsOnlyLowAndUndecided() {
        let actions = makeEightUndecidedActions()
        var mixed = actions
        mixed[0].userDecision = .approved
        mixed[1].userDecision = .undecided
        let lowUndecided = AppViewModel.lowRiskUndecidedActions(in: mixed)
        XCTAssertEqual(lowUndecided.count, 4)
        XCTAssertTrue(lowUndecided.allSatisfy { $0.risk == .low && $0.userDecision == .undecided })
        XCTAssertFalse(lowUndecided.contains { $0.id == "low-0" })
    }

    func testLowRiskUndecidedActionsEmptyWhenNone() {
        let actions = [makeAction(id: "medium-0", risk: .medium, decision: .undecided)]
        XCTAssertTrue(AppViewModel.lowRiskUndecidedActions(in: actions).isEmpty)
    }

    // MARK: - matchingActions(filter:in:)

    func testActionsMatchingNilFilterReturnsAll() {
        let actions = makeEightUndecidedActions()
        XCTAssertEqual(AppViewModel.matchingActions(filter: nil, in: actions).count, 8)
    }

    func testActionsMatchingHighExcludesForbidden() {
        let actions = makeEightUndecidedActions()
            + [makeAction(id: "forbidden-0", risk: .forbidden, decision: .undecided)]
        let high = AppViewModel.matchingActions(filter: .high, in: actions)
        XCTAssertEqual(high.count, 1)
        XCTAssertTrue(high.allSatisfy { $0.risk == .high })
        XCTAssertEqual(AppViewModel.matchingActions(filter: .forbidden, in: actions).count, 1)
    }

    func testActionsMatchingLowOnlyLow() {
        let actions = makeEightUndecidedActions()
        XCTAssertEqual(AppViewModel.matchingActions(filter: .low, in: actions).count, 5)
        XCTAssertTrue(AppViewModel.matchingActions(filter: .low, in: actions).allSatisfy { $0.risk == .low })
    }

    // MARK: - suggestionCommands

    func testSuggestionCommandsContainExpectedChips() {
        let commands = AppViewModel.suggestionCommands
        XCTAssertEqual(commands.count, 5)
        XCTAssertTrue(commands.contains("safe caches"))
        XCTAssertTrue(commands.contains("old installers"))
        XCTAssertTrue(commands.contains("duplicate files"))
        XCTAssertTrue(commands.contains("project leftovers"))
        XCTAssertTrue(commands.contains("everything"))
        // Chip identifiers must be unique for ForEach(id: \.self).
        XCTAssertEqual(Set(commands).count, commands.count)
    }
}
