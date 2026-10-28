import Foundation
import MacOSCleanerCore

// MARK: - Explore selection + staging (Agent 4 iteration 3)

/// Explore visualization selection and plan-staging behavior for AppViewModel.
/// Stored state lives on the main type (the `@Observable` macro cannot observe
/// extension stored properties); everything here is behavior. Staging never
/// touches the filesystem: it appends a Trash-first `PlannedAction` that flows
/// through user approval (`approve`), SafetyAuditor, and ActionExecutor like
/// any other plan action — the same pipeline `stageUninstall` uses.
@MainActor
extension AppViewModel {

    /// The currently selected Explore record, resolved against the scan cache.
    var selectedExploreRecord: FileRecord? {
        guard let id = selectedExploreRecordID else {
            return nil
        }
        return filesByID[id]
    }

    /// The currently focused (drilled-into) Explore record.
    var focusedExploreRecord: FileRecord? {
        guard let id = focusedExploreRecordID else {
            return nil
        }
        return filesByID[id]
    }

    /// Select an Explore group member by record id. Nil clears the selection.
    func selectExploreRecord(id: String?) {
        selectedExploreRecordID = id
    }

    /// Drill the Explore list into the given record. Nil zooms back out.
    func focusExploreRecord(id: String?) {
        focusedExploreRecordID = id
    }

    /// The existing plan action already staging this record, if any.
    func stagedExploreAction(matching record: FileRecord) -> PlannedAction? {
        plan?.actions.first { $0.targets == [record.id] }
    }

    /// Stages an Explore-selected record for cleanup as a proposed,
    /// Trash-first plan action. Returns the staged action, or nil when there
    /// is no plan yet (caller shows "run a scan first") or the record is
    /// already staged (returns the existing action). Never deletes directly:
    /// the action stays `.proposed`/undecided until the user approves it in
    /// Proposed Actions, and SafetyAuditor still reviews it at execution.
    @discardableResult
    func stageExploreRecordForCleanup(_ record: FileRecord) -> PlannedAction? {
        guard !isScanning, !isExecuting, !isPlanning else { return nil }
        if let existing = stagedExploreAction(matching: record) {
            return existing
        }
        guard var currentPlan = plan else {
            return nil
        }
        guard filesByID[record.id] != nil else {
            return nil
        }
        let action = PlannedAction(
            id: UUID().uuidString,
            planID: currentPlan.id,
            actionType: .moveToTrash,
            targets: [record.id],
            destination: nil,
            status: .proposed,
            risk: record.riskFlags.isEmpty ? .low : .medium,
            confidence: 0.7,
            reason: String(localized: "Staged from Explore: \(record.fileName) (\(record.sizeBytes.formattedByteCount))."),
            userDecision: .undecided,
            executedAt: nil,
            findingID: nil
        )
        currentPlan.actions.append(action)
        currentPlan.originalActions?.append(action)
        refreshPlanEstimates(plan: &currentPlan)
        plan = currentPlan
        selectedActionID = action.id
        statusMessage = String(localized: "Staged \(record.fileName) for review in Proposed Actions.")
        return action
    }

    /// Removes the staged Explore action for a record, if one exists.
    func unstageExploreAction(matching record: FileRecord) {
        guard !isScanning, !isExecuting, !isPlanning else { return }
        guard var currentPlan = plan else {
            return
        }
        let before = currentPlan.actions.count
        currentPlan.actions.removeAll { $0.targets == [record.id] && $0.status == .proposed }
        currentPlan.originalActions?.removeAll { $0.targets == [record.id] && $0.status == .proposed }
        guard currentPlan.actions.count != before else {
            return
        }
        refreshPlanEstimates(plan: &currentPlan)
        plan = currentPlan
        if selectedActionID.map({ id in !currentPlan.actions.contains(where: { $0.id == id }) }) ?? false {
            selectedActionID = currentPlan.actions.first?.id
        }
        statusMessage = String(localized: "Removed \(record.fileName) from the cleanup plan.")
    }
}
