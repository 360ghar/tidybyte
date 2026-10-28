import Foundation
import os

public actor PlannerAgent {
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "PlannerAgent")
    public init() {}

    public func makePlan(
        sessionID: String,
        recommendations: [Recommendation],
        filesByID: [String: FileRecord],
        aiRecommendations: [AIRecommendationPayload] = []
    ) -> Plan {
        var actions = recommendations.map { recommendation in
            PlannedAction(
                id: UUID().uuidString,
                planID: "",
                actionType: recommendation.actionType,
                targets: recommendation.targetFileIDs,
                destination: recommendation.destination,
                status: .proposed,
                risk: recommendation.risk,
                confidence: recommendation.confidence,
                reason: recommendation.reason,
                userDecision: .undecided,
                executedAt: nil,
                findingID: recommendation.findingID
            )
        }

        for payload in aiRecommendations {
            guard let target = filesByID[payload.targetFileID] else {
                continue
            }
            // Prompt-injection defense: the model's declared risk is untrusted
            // (a poisoned file snippet can claim "low"). Clamp to the floor
            // implied by the file's own risk flags so a secret/config file can
            // never be downgraded below what the deterministic policy says.
            let clampedRisk = max(payload.risk, Self.riskFloor(for: target.riskFlags))
            actions.append(PlannedAction(
                id: UUID().uuidString,
                planID: "",
                actionType: payload.action,
                targets: [payload.targetFileID],
                destination: nil,
                status: .proposed,
                risk: clampedRisk,
                confidence: min(payload.confidence, 0.85), // AI-only suggestions are capped at 0.85 to ensure human review; deterministic rules may exceed this
                reason: String(localized: "AI metadata-only suggestion: \(payload.reason)", comment: "Reason prefix for AI-generated recommendation"),
                userDecision: .undecided,
                executedAt: nil,
                findingID: nil
            ))
        }

        actions = actions.map { Self.demotingReviewOnly($0, filesByID: filesByID) }
        actions = dedupe(actions).sorted { lhs, rhs in
            if lhs.risk != rhs.risk {
                return lhs.risk < rhs.risk
            }
            return lhs.confidence > rhs.confidence
        }

        // Filter out recommendations below 0.40 confidence - too uncertain to act on
        actions = actions.filter { $0.confidence >= 0.40 }

        let planID = UUID().uuidString
        actions = actions.map { action in
            var updated = action
            updated.planID = planID
            return updated
        }

        // Sum sizes over the DEDUPED target set: the same file can appear in
        // multiple actions (different findings) and was being counted once each.
        let estimatedBytes = Set(actions.flatMap(\.targets))
            .compactMap { filesByID[$0]?.sizeBytes }
            .reduce(Int64(0), +)
        let riskBreakdown = Dictionary(grouping: actions, by: \.risk).mapValues(\.count)
        return Plan(
            id: planID,
            scanSessionID: sessionID,
            createdAt: Date(),
            status: .proposed,
            summary: summary(for: actions, estimatedBytes: estimatedBytes),
            estimatedReclaimableBytes: estimatedBytes,
            estimatedFilesAffected: Set(actions.flatMap(\.targets)).count,
            riskBreakdown: riskBreakdown,
            actions: actions
        )
    }

    public func planForNaturalLanguageCommand(
        _ command: String,
        existingPlan: Plan,
        filesByID: [String: FileRecord]
    ) -> Plan {
        let intent = IntentParser.parse(command)
        return plan(for: intent, existingPlan: existingPlan, filesByID: filesByID, rawCommand: command)
    }

    /// Applies a parsed `PlanIntent` to an existing plan. Public so tests can
    /// exercise intent handling without going through string parsing.
    /// `rawCommand` is unused and retained only for source compatibility with
    /// earlier call sites; the intent carries all parsed meaning.
    public func plan(
        for intent: PlanIntent,
        existingPlan: Plan,
        filesByID: [String: FileRecord],
        rawCommand _: String = ""
    ) -> Plan {
        var plan = existingPlan
        let originalActions = existingPlan.originalActions ?? existingPlan.actions
        plan.actions = originalActions

        // --- Phase 1: Action type transformations (not filters) ---
        switch intent.action {
        case .archive:
            plan.actions = plan.actions.map { action in
                var updated = action
                if updated.actionType == .tag || updated.actionType == .inspectOnly {
                    updated.actionType = .archive
                    updated.reason += String(localized: " Natural-language command requested archive-oriented organization.", comment: "Reason suffix for archive-oriented NL command")
                }
                return updated
            }
        case .delete:
            plan.actions = plan.actions.map { action in
                var updated = action
                if updated.risk == .low && updated.actionType != .moveToTrash {
                    updated.actionType = .moveToTrash
                    updated.reason += String(localized: " Natural-language command requested removal.", comment: "Reason suffix for delete/trash/remove NL command")
                }
                return updated
            }
        case .organize:
            plan.actions = plan.actions.map { action in
                var updated = action
                if updated.actionType == .tag || updated.actionType == .inspectOnly {
                    guard let destination = organizationDestination(for: updated, filesByID: filesByID) else {
                        return updated
                    }
                    updated.actionType = .move
                    updated.destination = destination
                    updated.reason += String(localized: " Natural-language command requested file organization.", comment: "Reason suffix for organize/sort NL command")
                }
                return updated
            }
        case .review:
            break
        }

        // --- Phase 2: Filters from the parsed intent (OR logic) ---
        var filters: [(PlannedAction) -> Bool] = []
        var summaryText: String?

        for scope in intent.scopes {
            switch scope {
            case .all, .restoreAll:
                break
            case .pythonCaches:
                filters.append { action in
                    action.targets.contains { target in
                        guard let record = filesByID[target] else { return target.contains("pip") }
                        return record.url.pathComponents.contains("__pycache__")
                            || record.url.pathComponents.contains(".pytest_cache")
                            || record.url.pathComponents.contains(".venv")
                            || record.url.pathComponents.contains("venv")
                    }
                }
                summaryText = String(localized: "Python caches and environments", comment: "Natural language summary fragment for Python cache filter")
            case .largerThan(let bytes):
                filters.append { action in
                    action.targets.contains { (filesByID[$0]?.sizeBytes ?? 0) >= bytes }
                }
                summaryText = bytes >= 1_000_000_000
                    ? String(localized: "large files (1GB+)", comment: "Natural language summary fragment for large files filter")
                    : String(localized: "large items (100MB+)", comment: "Natural language summary fragment for broad large item filter")
            case .duplicates:
                let allTargetCounts = Dictionary(plan.actions.flatMap { $0.targets }.map { ($0, 1) }, uniquingKeysWith: +)
                let sharedTargets = Set(allTargetCounts.filter { $0.value > 1 }.map(\.key))
                filters.append { action in
                    action.actionType == .cloneDeduplicate
                        || action.reason.lowercased().contains("duplicate")
                        || action.targets.contains { sharedTargets.contains($0) }
                }
                summaryText = String(localized: "duplicate files", comment: "Natural language summary fragment for duplicate files filter")
            case .olderThan(let days):
                let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                summaryText = String(localized: "files older than \(days) days", comment: "Natural language summary fragment for old files filter")
                filters.append { action in
                    action.targets.contains { target in
                        guard let record = filesByID[target] else { return false }
                        return (record.modifiedAt ?? record.createdAt ?? Date.distantPast) < cutoff
                    }
                }
            case .oldDownloads(let days):
                let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                filters.append { action in
                    action.targets.contains { target in
                        guard let record = filesByID[target] else { return false }
                        return (record.modifiedAt ?? record.createdAt ?? Date.distantPast) < cutoff
                            && record.url.pathComponents.contains("Downloads")
                    }
                }
                summaryText = String(localized: "old files in Downloads", comment: "Natural language summary fragment for old Downloads filter")
            case .downloads:
                filters.append { action in
                    action.targets.contains { filesByID[$0]?.url.pathComponents.contains("Downloads") ?? false }
                }
                summaryText = summaryText ?? String(localized: "Downloads folder", comment: "Natural language summary fragment for Downloads filter")
            case .caches:
                filters.append { action in
                    action.targets.contains { target in
                        guard let record = filesByID[target] else { return false }
                        return Self.isCacheOrTemporaryPath(record.url.pathComponents)
                            || action.reason.lowercased().contains("cache")
                    }
                }
                summaryText = summaryText ?? String(localized: "caches and temporary files", comment: "Natural language summary fragment for cache filter")
            case .logs:
                filters.append { action in
                    action.targets.contains { target in
                        guard let record = filesByID[target] else { return false }
                        return record.fileExtension == "log"
                            || record.url.pathComponents.contains("Logs")
                            || record.url.pathComponents.contains("logs")
                    }
                }
                summaryText = String(localized: "log files", comment: "Natural language summary fragment for log filter")
            case .docker:
                filters.append { action in
                    if action.actionType == .runPackageManagerCleanup && action.targets.contains(where: { $0.contains("docker") }) { return true }
                    return action.targets.contains { target in
                        guard let record = filesByID[target] else { return false }
                        return record.url.pathComponents.contains("Docker") || record.url.pathComponents.contains("docker")
                            || record.fileName.lowercased().contains("docker")
                    }
                }
                summaryText = String(localized: "Docker cleanup", comment: "Natural language summary fragment for Docker filter")
            case .nodeModules:
                filters.append { action in
                    action.targets.contains { target in
                        guard let record = filesByID[target] else { return false }
                        return record.url.pathComponents.contains("node_modules")
                            || record.url.pathComponents.contains(".npm")
                            || record.fileName.lowercased().contains("npm")
                    }
                }
                summaryText = String(localized: "npm and Node.js cleanup", comment: "Natural language summary fragment for npm and Node cleanup filter")
            case .homebrew:
                filters.append { action in
                    action.actionType == .runPackageManagerCleanup && action.targets.contains { $0.contains("brew") || $0.contains("homebrew") }
                }
                summaryText = String(localized: "Homebrew cleanup", comment: "Natural language summary fragment for Homebrew filter")
            case .developerArtifacts:
                filters.append { action in
                    action.targets.contains { target in
                        guard let record = filesByID[target] else { return false }
                        return record.url.pathComponents.contains(where: { ["node_modules", "__pycache__", ".venv", "DerivedData", "target", "build", "dist"].contains($0) })
                            || action.reason.lowercased().contains("developer")
                            || action.reason.lowercased().contains("build artifact")
                    }
                }
                summaryText = String(localized: "developer artifacts", comment: "Natural language summary fragment for developer artifacts filter")
            case .safeOnly:
                break
            }
        }

        if intent.action == .organize {
            filters.append { action in
                action.actionType == .tag || action.actionType == .archive
                    || action.actionType == .createAlias || action.actionType == .createSymlink
                    || action.actionType == .move
            }
            summaryText = String(localized: "organization suggestions", comment: "Natural language summary fragment for organize filter")
        }

        // Apply all collected filters with OR logic (not cumulative AND)
        if !filters.isEmpty {
            plan.actions = plan.actions.filter { action in filters.contains { $0(action) } }
            plan.summary = String(localized: "Targeted plan: \(summaryText ?? "filtered").", comment: "Plan summary for NL filter")
        }

        if intent.scopes.contains(.safeOnly) {
            plan.actions = plan.actions.filter { $0.risk == .low }
            if !filters.isEmpty {
                plan.summary = String(localized: "Targeted safe plan: \(summaryText ?? "filtered").", comment: "Plan summary for targeted safe-only filter")
            } else {
                plan.summary = String(localized: "Filtered to safe-only (low risk) actions.", comment: "Plan summary for safe-only filter")
            }
        }

        // "everything" / "show all" / "full restore" / "undo" / "reset" — restore original actions.
        // Driven by the parsed intent now, not raw-string matching, so the
        // grammar owns the vocabulary in one place.
        var didRestore = false
        if intent.scopes.contains(.restoreAll) {
            if let original = plan.originalActions {
                plan.actions = original
                plan.originalActions = nil
                plan.summary = String(localized: "Restored all original actions.", comment: "Plan summary for restore-all filter")
                didRestore = true
            }
        }

        if !didRestore && plan.originalActions == nil {
            plan.originalActions = originalActions
        }
        refreshEstimates(&plan, filesByID: filesByID)
        return plan
    }

    private func refreshEstimates(_ plan: inout Plan, filesByID: [String: FileRecord]) {
        plan.estimatedReclaimableBytes = Set(plan.actions.flatMap(\.targets))
            .compactMap { filesByID[$0]?.sizeBytes }
            .reduce(Int64(0), +)
        plan.estimatedFilesAffected = Set(plan.actions.flatMap(\.targets)).count
        plan.riskBreakdown = Dictionary(grouping: plan.actions, by: \.risk).mapValues(\.count)
    }

    private static func isCacheOrTemporaryPath(_ components: [String]) -> Bool {
        for (index, component) in components.enumerated() {
            let lowered = component.lowercased()
            if lowered == "caches" || lowered == "cache" || lowered == ".cache" || lowered == "__pycache__" {
                return true
            }
            if (lowered == "tmp" || lowered == "temp") && !isSystemTemporaryRoot(components, index: index) {
                return true
            }
        }
        return false
    }

    private static func isSystemTemporaryRoot(_ components: [String], index: Int) -> Bool {
        guard components[index].lowercased() == "tmp" else {
            return false
        }
        // URL.pathComponents for /tmp/foo is ["/", "tmp", "foo"], and for
        // /private/tmp/foo it is ["/", "private", "tmp", "foo"]. Those scan
        // roots should not make every child file match a cache/temporary query.
        if index == 1 {
            return true
        }
        return index == 2 && components.indices.contains(1) && components[1].lowercased() == "private"
    }

    /// Computes an "Organized" destination folder for a move action produced by an
    /// organize/sort natural-language command. The destination is the deepest common
    /// parent directory of the action's targets plus "Organized", which is inside the
    /// scanned root by construction (targets are scanned files). The filesystem root
    /// is never used as a base.
    private func organizationDestination(for action: PlannedAction, filesByID: [String: FileRecord]) -> URL? {
        let parentURLs = action.targets.compactMap { filesByID[$0]?.url.deletingLastPathComponent() }
        guard let firstParent = parentURLs.first else {
            return nil
        }
        let commonParent = parentURLs.dropFirst().reduce(firstParent) { common, next in
            commonAncestor(of: common, and: next) ?? common
        }
        let isRoot = commonParent.path == "/" || commonParent.path.isEmpty
        let base = isRoot ? firstParent : commonParent
        return base.appendingPathComponent("Organized", isDirectory: true)
    }

    private func commonAncestor(of lhs: URL, and rhs: URL) -> URL? {
        let lhsComponents = lhs.standardizedFileURL.pathComponents
        let rhsComponents = rhs.standardizedFileURL.pathComponents
        var common: [String] = []
        for (l, r) in zip(lhsComponents, rhsComponents) where l == r {
            common.append(l)
        }
        guard !common.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: common.joined(separator: "/"), isDirectory: true)
    }

    private func dedupe(_ actions: [PlannedAction]) -> [PlannedAction] {
        var seen: Set<String> = []
        return actions.filter { action in
            // Include findingID in the key so the same file flagged by different findings
            // (e.g., as both a "duplicate" and a "large file") is not lost during dedup.
            let findingKey = action.findingID ?? ""
            let key = "\(action.actionType.rawValue)-\(findingKey)-\(action.targets.sorted().joined(separator: ","))"
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    /// Lowest risk level a file with these flags may carry. Files flagged by the
    /// deterministic safety policy cannot be downgraded by AI-declared risk.
    /// Public so the Explore inspector stages user-pinned files at the same
    /// floor instead of duplicating this safety mapping in the UI layer.
    /// Review-only targets stay visible but can never be approved for a change.
    static func demotingReviewOnly(_ action: PlannedAction, filesByID: [String: FileRecord]) -> PlannedAction {
        guard action.targets.contains(where: { filesByID[$0]?.riskFlags.contains(.reviewOnly) == true }) else {
            return action
        }
        var demoted = action
        demoted.actionType = .inspectOnly
        demoted.risk = max(action.risk, .high)
        return demoted
    }

    public static func riskFloor(for flags: Set<RiskFlag>) -> RiskLevel {
        if flags.contains(.sipProtectedSystemPath) || flags.contains(.insideTrash)
            || flags.contains(.protectedDirectory) || flags.contains(.protectedFile) {
            return .forbidden
        }
        if flags.contains(.secretOrCertificate) || flags.contains(.cloudSyncedLocalPath)
            || flags.contains(.codingAgentMemoryOrConfig) || flags.contains(.reviewOnly) {
            return .high
        }
        if flags.contains(.projectManifest) || flags.contains(.sourceOrConfig) {
            return .medium
        }
        return .low
    }

    private func summary(for actions: [PlannedAction], estimatedBytes: Int64) -> String {
        if actions.isEmpty {
            return String(localized: "No cleanup actions are currently recommended.", comment: "Plan summary when no actions exist")
        }
        let low = actions.filter { $0.risk == .low }.count
        let medium = actions.filter { $0.risk == .medium }.count
        let high = actions.filter { $0.risk == .high }.count
        return String(localized: "\(actions.count) proposed actions: \(low) low risk, \(medium) medium risk, \(high) high risk. Estimated reviewable space: \(estimatedBytes.formattedByteCount).", comment: "Plan summary with action counts and sizes")
    }

    /// Appends staged recommendations (e.g. an app uninstall from
    /// ApplicationFootprintService) to an existing plan without rebuilding it.
    /// Returns the actions to append with plan IDs stamped; the caller merges
    /// them into its own plan state. Skips staged targets already covered by
    /// an existing action so re-staging the same app never double-counts.
    public func appendRecommendations(
        _ recommendations: [Recommendation],
        to plan: Plan,
        filesByID: [String: FileRecord]
    ) -> [PlannedAction] {
        var coveredTargets = Set(plan.actions.flatMap(\.targets))
        var appended: [PlannedAction] = []
        for recommendation in recommendations {
            let freshTargets = recommendation.targetFileIDs.filter { coveredTargets.insert($0).inserted }
            guard !freshTargets.isEmpty, freshTargets.allSatisfy({ filesByID[$0] != nil }) else { continue }
            appended.append(Self.demotingReviewOnly(PlannedAction(
                id: UUID().uuidString,
                planID: plan.id,
                actionType: recommendation.actionType,
                targets: freshTargets,
                destination: recommendation.destination,
                status: .proposed,
                risk: recommendation.risk,
                confidence: recommendation.confidence,
                reason: recommendation.reason,
                userDecision: .undecided,
                executedAt: nil,
                findingID: recommendation.findingID
            ), filesByID: filesByID))
        }
        return appended
    }

    /// Builds the resolution action(s) for one exact-duplicate finding under
    /// the given strategy: a clone-fold action (keeper as destination) and/or
    /// a trash action for members that cannot be folded. Used by the
    /// Duplicates tab's per-group strategy switch; mirrors what the detector
    /// emits at scan time so a swap never disagrees with a fresh scan.
    public static func duplicateResolutionActions(
        for finding: Finding,
        filesByID: [String: FileRecord],
        strategy: DuplicateStrategy,
        planID: String
    ) -> [PlannedAction] {
        guard let (keep, duplicates) = DuplicateDetector.keeperAndDuplicates(
            of: finding.targetFileIDs, filesByID: filesByID
        ) else {
            return []
        }
        var actions: [PlannedAction] = []
        func appendAction(_ actionType: ActionType, targets: [FileRecord], reason: String) {
            actions.append(PlannedAction(
                id: UUID().uuidString,
                planID: planID,
                actionType: actionType,
                targets: targets.map(\.id),
                destination: actionType == .cloneDeduplicate ? keep.url : nil,
                status: .proposed,
                risk: actionType == .cloneDeduplicate ? .low : finding.severity,
                confidence: finding.confidence,
                reason: reason,
                userDecision: .undecided,
                executedAt: nil,
                findingID: finding.id
            ))
        }
        let foldEligible = strategy == .apfsClone
            ? DuplicateDetector.foldEligibleDuplicates(duplicates: duplicates, keep: keep)
            : []
        if !foldEligible.isEmpty {
            appendAction(
                .cloneDeduplicate,
                targets: foldEligible,
                reason: String(
                    localized: """
                    Fold each copy onto the newest file as an APFS clone. Every file keeps its \
                    name, contents and metadata. Nothing is deleted, the space is reclaimed \
                    immediately, and this can be undone.
                    """,
                    comment: "Exact duplicate clone-fold recommendation reason"
                )
            )
        }
        let eligibleIDs = Set(foldEligible.map(\.id))
        let trashTargets = strategy == .moveToTrash ? duplicates : duplicates.filter { !eligibleIDs.contains($0.id) }
        if !trashTargets.isEmpty {
            appendAction(
                .moveToTrash,
                targets: trashTargets,
                reason: String(localized: "These files have the same size and full content hash. Keep the newest copy and move duplicate copies to Trash.", comment: "Exact duplicate recommendation reason")
            )
        }
        return actions
    }
}
