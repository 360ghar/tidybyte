import Foundation
import MacOSCleanerCore

// MARK: - Review flow helpers

/// Pure review-flow helpers used by the action review UI (ActionStackView and
/// NaturalLanguagePlanView). All members are static and compute only over the
/// plan's actions; none mutate AppViewModel state, so they are safe to call
/// from view code and unit tests.
///
/// No stored properties live in this extension: the `@Observable` macro cannot
/// observe extension stored properties, and all state flows through the
/// existing `plan` property.
@MainActor
extension AppViewModel {

    /// Finding category per finding ID, for routing actions to sidebar rows.
    private var findingCategories: [String: FindingCategory] {
        Dictionary((outcome?.findings ?? []).map { ($0.id, $0.category) }, uniquingKeysWith: { first, _ in first })
    }

    /// The plan actions that belong to one sidebar row.
    func actions(in destination: AppDestination) -> [PlannedAction] {
        let categories = findingCategories
        return (plan?.actions ?? []).filter {
            AppDestination.forCategory($0.findingID.flatMap { categories[$0] }) == destination
        }
    }

    /// Bytes still waiting for a decision, per sidebar row (sidebar badges).
    var pendingBytesByDestination: [AppDestination: Int64] {
        let categories = findingCategories
        let files = filesByID
        var targets: [AppDestination: Set<String>] = [:]
        for action in plan?.actions ?? [] where action.executedAt == nil && action.userDecision != .rejected {
            let row = AppDestination.forCategory(action.findingID.flatMap { categories[$0] })
            targets[row, default: []].formUnion(action.targets)
        }
        return targets.mapValues { ids in
            ids.compactMap { files[$0].map { ReclaimableBytes.size(of: $0, checkClones: false) } }.reduce(0, +)
        }
    }

    var visibleReviewActions: [PlannedAction] {
        Self.matchingActions(filter: reviewRiskFilter, in: actions(in: destination)).filter(actionMatchesSearch)
    }

    /// Menu commands must act on a row visible in the current review list.
    var selectedVisibleReviewAction: PlannedAction? {
        guard destination.isReview, let id = selectedActionID else { return nil }
        return visibleReviewActions.first { $0.id == id }
    }

    func showReviewAction(id: String) {
        reviewRiskFilter = nil
        searchText = ""
        selectedActionID = id
        let action = plan?.actions.first { $0.id == id }
        destination = AppDestination.forCategory(action?.findingID.flatMap { findingCategories[$0] })
        showsInspector = true
    }

    /// The toolbar Scan button: personal folders and Photos through Cleanup,
    /// plus the system scan with the saved scope (direct build only).
    func scanAll() {
        // The direct build can read the personal folders without per-folder grants;
        // the sandboxed build must ask through the scope sheet (cleanup.scan opens it).
        if cleanup.scope.roots.isEmpty, DistributionChannel.supportsAdvanced {
            cleanup.scope.mode = .fullMac
            cleanup.scope.roots = ReviewScope.presetFolders
                .map { ReviewSafety.userHome.appendingPathComponent($0) }
                .filter(Self.isLocalFolder)
        }
        cleanup.scan()
        guard DistributionChannel.supportsAdvanced else { return }
        if selectedMode == .selectedFolders && selectedFolders.isEmpty {
            selectedMode = .homeFolder
            saveSettings()
        }
        runScan()
    }

    /// A real local folder: one missing, symlinked, or on another volume would stop the scan.
    static func isLocalFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeIsLocalKey])
        return values?.isDirectory == true && values?.isSymbolicLink == false && values?.volumeIsLocal != false
    }

    /// The actions that match a risk filter chip. Forbidden actions have their
    /// own chip; the "High" chip matches high-risk only. A nil filter matches all.
    static func matchingActions(filter: RiskLevel?, in actions: [PlannedAction]) -> [PlannedAction] {
        guard let filter else {
            return actions
        }
        return actions.filter { $0.risk == filter }
    }

    /// Number of undecided actions currently visible under a risk filter.
    static func visibleUndecidedCount(actions: [PlannedAction], filter: RiskLevel?) -> Int {
        matchingActions(filter: filter, in: actions).filter { $0.userDecision == .undecided }.count
    }

    /// The exact approve set for "Approve Visible": every undecided action
    /// matching the current risk filter. ActionStackView snapshots this once
    /// at confirmation-presentation time so the dialog copy and the approval
    /// loop always agree (G-01); decided actions are never included.
    static func actionsToApprove(actions: [PlannedAction], filter: RiskLevel?) -> [PlannedAction] {
        matchingActions(filter: filter, in: actions).filter { $0.userDecision == .undecided }
    }

    /// Every undecided action regardless of risk (bulk "Reject Undecided").
    static func undecidedActions(in actions: [PlannedAction]) -> [PlannedAction] {
        actions.filter { $0.userDecision == .undecided }
    }

    /// Undecided low-risk actions (bulk "Approve Low Risk").
    static func lowRiskUndecidedActions(in actions: [PlannedAction]) -> [PlannedAction] {
        actions.filter { $0.risk == .low && $0.userDecision == .undecided }
    }

    /// The suggestion chips shown above the natural-language field. Clicking
    /// one applies the command through the same NL pipeline as a typed request.
    static var suggestionCommands: [String] {
        [
            String(localized: "safe caches"),
            String(localized: "old installers"),
            String(localized: "duplicate files"),
            String(localized: "project leftovers"),
            String(localized: "everything")
        ]
    }
}
