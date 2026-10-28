import Foundation
import os

public actor MemoryEngine {
    private let store: SQLiteStore
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "MemoryEngine")

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func applyMemory(to recommendations: [Recommendation], filesByID: [String: FileRecord]) async throws -> [Recommendation] {
        let rawRules = try await store.loadMemoryRules()
        guard !rawRules.isEmpty else {
            return recommendations
        }
        // Sort rules by scope specificity (most specific first) so that a directory-scoped
        // rule is applied before a global rule. Without this, a newer global rule created
        // after a directory rule would shadow the more specific rule due to the short-circuit.
        // Within the same specificity, newer rules (higher createdAt) take precedence.
        let rules = rawRules.sorted { lhs, rhs in
            let lhsRank = Self.scopeSpecificity(lhs.scopeType)
            let rhsRank = Self.scopeSpecificity(rhs.scopeType)
            if lhsRank != rhsRank {
                return lhsRank > rhsRank
            }
            return lhs.createdAt > rhs.createdAt
        }

        return recommendations.map { recommendation in
            var adjusted = recommendation
            let records = recommendation.targetFileIDs.compactMap { filesByID[$0] }
            // Apply the first matching rule only (short-circuit) to avoid unpredictable stacking.
            // More specific rules (directory/file scope) should be stored with higher confidence
            // and will naturally be matched first if rules are sorted by scope specificity.
            for rule in rules where ruleMatches(rule, records: records, recommendation: recommendation) {
                // Use structured ruleType when available; fall back to substring matching for legacy rules.
                let effectiveType = rule.ruleType ?? Self.inferRuleType(from: rule.rule)
                switch effectiveType {
                case .never:
                    adjusted.risk = max(adjusted.risk, .high)
                    adjusted.confidence = min(adjusted.confidence, 0.55)
                    adjusted.reason += String(localized: " Memory rule applied: \(rule.rule)", comment: "Suffix appended to reason when a memory rule is applied")
                    // "Never" suppresses every destructive action, not just trash —
                    // the user said no to this file, so .move/.archive are equally unwanted.
                    // A fold rewrites the file's inode too, so it is equally unwanted.
                    switch adjusted.actionType {
                    case .moveToTrash, .move, .rename, .archive, .cloneDeduplicate:
                        adjusted.actionType = .inspectOnly
                    default:
                        break
                    }
                case .preferArchive:
                    adjusted.actionType = .archive
                    adjusted.reason += String(localized: " Memory rule applied: \(rule.rule)", comment: "Suffix appended to reason when a memory rule is applied")
                case .always:
                    adjusted.confidence = min(1.0, adjusted.confidence + 0.15)
                    adjusted.reason += String(localized: " Memory rule applied: \(rule.rule)", comment: "Suffix appended to reason when a memory rule is applied")
                }
                break // Short-circuit: first matching rule wins
            }
            return adjusted
        }
    }

    private static let directoryScopeType = "directory"
    private static let fileScopeType = "file"
    private static let globalScopeType = "global"

    /// Rank scope types by specificity so more specific scopes are applied first.
    /// Higher number = more specific. Used to sort rules before short-circuit application.
    private static let scopeRanks: [String: Int] = [
        fileScopeType: 5,
        directoryScopeType: 4,
        "projectType": 3,
        "cloudProvider": 3,
        "extension": 2,
        globalScopeType: 1
    ]

    private static func scopeSpecificity(_ scopeType: String) -> Int {
        scopeRanks[scopeType] ?? 0
    }

    /// Saves a memory rule, or REINFORCES an existing rule that matches on
    /// (scopeType, scopeValue, actionType, ruleType) instead of inserting a
    /// duplicate. Duplicate rules previously accumulated because
    /// learn/detectPatterns/recordRegret each inserted a fresh row without
    /// checking for an existing one; reinforcement keeps one row per decision
    /// and bumps its recency/confidence.
    ///
    /// When `matchOnRuleText` is true, the rule TEXT is also part of the
    /// identity — used by calibration preferences, where the free text IS the
    /// preference (two different "never" presets must not merge into one rule).
    private func saveOrReinforceRule(
        scopeType: String,
        scopeValue: String,
        actionType: ActionType?,
        ruleType: MemoryRuleType,
        rule: String,
        source: String,
        confidence: Double,
        matchOnRuleText: Bool = false
    ) async throws {
        let existing = try await store.loadMemoryRules()
            .first { candidate in
                candidate.scopeType == scopeType
                    && candidate.scopeValue == scopeValue
                    && candidate.actionType == actionType
                    && candidate.ruleType == ruleType
                    && (!matchOnRuleText || candidate.rule == rule)
            }
        let ruleToSave: MemoryRule
        if let existing {
            ruleToSave = MemoryRule(
                id: existing.id,
                scopeType: existing.scopeType,
                scopeValue: existing.scopeValue,
                rule: rule,
                source: source,
                confidence: max(existing.confidence, confidence),
                createdAt: existing.createdAt,
                lastReinforcedAt: Date(),
                ruleType: existing.ruleType,
                actionType: existing.actionType
            )
        } else {
            ruleToSave = MemoryRule(
                id: UUID().uuidString,
                scopeType: scopeType,
                scopeValue: scopeValue,
                rule: rule,
                source: source,
                confidence: confidence,
                createdAt: Date(),
                lastReinforcedAt: nil,
                ruleType: ruleType,
                actionType: actionType
            )
        }
        try await store.saveMemoryRule(ruleToSave)
    }

    public func learn(from action: PlannedAction, filesByID: [String: FileRecord]) async throws {
        guard action.userDecision == .alwaysDoThis || action.userDecision == .neverDoThisHere else {
            return
        }
        let records = action.targets.compactMap { filesByID[$0] }
        guard let first = records.first else {
            return
        }
        let ruleText: String
        let ruleType: MemoryRuleType
        if action.userDecision == .alwaysDoThis {
            ruleText = String(localized: "Always consider \(action.actionType.rawValue) for \(first.fileName) in this scope after review.", comment: "Memory rule for always-do action")
            ruleType = .always
        } else {
            ruleText = String(localized: "Never suggest \(action.actionType.rawValue) in \(first.url.deletingLastPathComponent().path).", comment: "Memory rule for never-do action")
            ruleType = .never
        }
        try await saveOrReinforceRule(
            scopeType: Self.directoryScopeType,
            scopeValue: first.url.deletingLastPathComponent().path,
            actionType: action.actionType,
            ruleType: ruleType,
            rule: ruleText,
            source: String(localized: "explicit user setting", comment: "Source label for user-initiated memory rule"),
            confidence: 0.9
        )
    }

    public func detectPatterns(from history: [PlannedAction], filesByID: [String: FileRecord]) async throws {
        // Count rejections/approvals by action type and directory (not individual file ID,
        // so that patterns across different files in the same directory are detected).
        var rejectionCounts: [String: Int] = [:]
        var approvalCounts: [String: Int] = [:]
        // Cache the directory for each key so we don't re-derive it during rule creation.
        var keyToDirectory: [String: String] = [:]

        for action in history {
            guard let firstTarget = action.targets.first.flatMap({ filesByID[$0] }) else { continue }
            let directory = firstTarget.url.deletingLastPathComponent().path
            let key = "\(action.actionType.rawValue)\t\(directory)"
            keyToDirectory[key] = directory
            switch action.userDecision {
            case .neverDoThisHere:
                rejectionCounts[key, default: 0] += 1
            case .alwaysDoThis:
                approvalCounts[key, default: 0] += 1
            default:
                break
            }
        }

        // Auto-generate rules for frequently rejected patterns (3+ rejections)
        for (key, count) in rejectionCounts where count >= 3 {
            let parts = key.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let directory = keyToDirectory[key] ?? String(parts[1])
            let ruleType: ActionType? = ActionType(rawValue: String(parts[0]))
            try await saveOrReinforceRule(
                scopeType: Self.directoryScopeType,
                scopeValue: directory,
                actionType: ruleType,
                ruleType: .never,
                rule: String(localized: "Never suggest \(parts[0]) in this directory (rejected \(count) times).", comment: "Auto-learned memory rule from rejection pattern"),
                source: String(localized: "learned decision", comment: "Source label for learned memory rule"),
                confidence: 0.8
            )
        }

        // Auto-generate rules for frequently approved patterns (3+ approvals)
        for (key, count) in approvalCounts where count >= 3 {
            let parts = key.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let directory = keyToDirectory[key] ?? String(parts[1])
            let ruleType: ActionType? = ActionType(rawValue: String(parts[0]))
            try await saveOrReinforceRule(
                scopeType: Self.directoryScopeType,
                scopeValue: directory,
                actionType: ruleType,
                ruleType: .always,
                rule: String(localized: "Always consider \(parts[0]) in this directory (approved \(count) times).", comment: "Auto-learned memory rule from approval pattern"),
                source: String(localized: "learned decision", comment: "Source label for learned memory rule"),
                confidence: 0.8
            )
        }
    }

    public func applyCalibrationPreference(
        _ preference: String,
        scopeType: String = "global",
        scopeValue: String = ""
    ) async throws {
        let ruleType = Self.inferRuleType(from: preference)
        try await saveOrReinforceRule(
            scopeType: scopeType,
            scopeValue: scopeValue,
            actionType: nil,
            ruleType: ruleType,
            rule: preference,
            source: String(localized: "explicit user setting", comment: "Source label for user calibration preference"),
            confidence: 0.95,
            // The preference text IS the rule identity: two different "never"
            // presets must stay separate rules.
            matchOnRuleText: true
        )
    }

    /// Records a regret event and creates a "never" memory rule keyed by the
    /// restored file's filesystem path, so the rule matches the same real path
    /// in future scans (per-scan file UUIDs never match records from later
    /// scans). `restoredFilePath` is preferred when available; otherwise the
    /// path is derived from `restoredFileID` when it is already a path (the
    /// UndoManagerService fallback when no file_id was recorded).
    public func recordRegret(operationLogID: String, restoredFileID: String, reason: String, restoredFilePath: String? = nil) async throws {
        let event = RegretEvent(
            id: UUID().uuidString,
            operationLogID: operationLogID,
            restoredFileID: restoredFileID,
            reason: reason,
            createdAt: Date(),
            ruleAdjustments: [String(localized: "Lower confidence for similar cleanup suggestions.", comment: "Rule adjustment when regret is recorded")]
        )
        try await store.saveRegretEvent(event)
        let pathKey = restoredFilePath ?? (restoredFileID.hasPrefix("/") ? restoredFileID : nil)
        // Scope the rule to the regretted action type when the operation log is
        // available; otherwise it applies to all action types.
        let ruleActionType = (try? await store.loadOperationLog(id: operationLogID))?.operationType
        try await saveOrReinforceRule(
            scopeType: Self.fileScopeType,
            scopeValue: pathKey ?? restoredFileID,
            actionType: ruleActionType,
            ruleType: .never,
            rule: String(localized: "Never repeat similar cleanup without manual review. Regret reason: \(reason)", comment: "Memory rule generated from regret event"),
            source: String(localized: "regret", comment: "Source label for regret-initiated memory rule"),
            confidence: 0.95
        )
    }

    /// Infer rule type from free text for legacy rules that don't have a structured `ruleType` field.
    private static func inferRuleType(from text: String) -> MemoryRuleType {
        if text.localizedCaseInsensitiveContains("prefer archive") {
            return .preferArchive
        } else if text.localizedCaseInsensitiveContains("never") {
            return .never
        } else {
            return .always
        }
    }

    private func ruleMatches(_ rule: MemoryRule, records: [FileRecord], recommendation: Recommendation) -> Bool {
        // A rule learned from one action type only applies to candidates of that
        // type, so a "never" rule for moveToTrash cannot over-suppress tag or
        // archive suggestions. Legacy rules without a recorded action type (and
        // free-text calibration preferences) apply to all action types.
        if let ruleActionType = rule.actionType, ruleActionType != recommendation.actionType {
            return false
        }
        switch rule.scopeType {
        case "global":
            return true
        case "directory":
            // Use scopeValue + "/" to ensure proper directory boundary matching.
            // Without the trailing slash, "/Users/me/Documents" would match "/Users/me/DocumentsImportant/file".
            let prefix = rule.scopeValue.hasSuffix("/") ? rule.scopeValue : rule.scopeValue + "/"
            return records.contains { $0.displayPath.hasPrefix(prefix) || $0.displayPath == rule.scopeValue }
        case "extension":
            return records.contains { $0.fileExtension == rule.scopeValue }
        case "file":
            // Match by file ID (legacy, same-session rules) or by filesystem path
            // so path-keyed rules (e.g. regret rules) match records from later
            // scans whose per-scan UUIDs are fresh.
            return recommendation.targetFileIDs.contains(rule.scopeValue)
                || records.contains { $0.displayPath == rule.scopeValue || $0.url.path == rule.scopeValue }
        case "projectType":
            // Match files whose path contains the project type identifier
            return records.contains { $0.url.path.lowercased().contains(rule.scopeValue.lowercased()) }
        case "cloudProvider":
            return records.contains { $0.cloudProvider?.lowercased() == rule.scopeValue.lowercased() }
        default:
            return false
        }
    }
}
