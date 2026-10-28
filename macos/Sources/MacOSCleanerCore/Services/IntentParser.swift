import Foundation

/// Structured natural-language intent: what the user wants done, to which
/// scope, in which location. Produced by `IntentParser` (pure, testable) and
/// consumed by `PlannerAgent.makePlan(intent:...)`. Replaces the previous
/// keyword `contains/regex` OR-filter stack, whose overlapping predicates
/// (`large` vs `large files`, `downloads` vs `old downloads`) produced
/// order-dependent, untestable plans.
public struct PlanIntent: Sendable, Equatable {
    public enum Action: String, Sendable {
        case review
        case delete
        case archive
        case organize
    }

    public enum Scope: Sendable, Equatable {
        case all
        case restoreAll
        case duplicates
        case caches
        case logs
        case downloads
        case oldDownloads(days: Int)
        case olderThan(days: Int)
        case largerThan(bytes: Int64)
        case pythonCaches
        case nodeModules
        case docker
        case homebrew
        case developerArtifacts
        case safeOnly
    }

    public var action: Action
    public var scopes: [Scope]

    public init(action: Action = .review, scopes: [Scope] = [.all]) {
        self.action = action
        self.scopes = scopes
    }
}

/// Pure rules-based grammar for plan commands. No LLM, no regex soup:
/// one tokenizer pass, then deterministic action + scope extraction.
public enum IntentParser {
    public static func parse(_ command: String) -> PlanIntent {
        let lowered = command.lowercased()
        let words = Set(lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        var action: PlanIntent.Action = .review
        if words.contains("archive") {
            action = .archive
        } else if words.isDisjoint(with: ["delete", "trash", "remove"]) == false {
            action = .delete
        } else if words.isDisjoint(with: ["organize", "sort"]) == false {
            action = .organize
        }

        var scopes: [PlanIntent.Scope] = []
        let wantsRestore = words.contains("everything") || lowered.contains("all actions")
            || words.isDisjoint(with: ["undo", "reset"]) == false
            || (words.contains("full") && words.isDisjoint(with: ["show", "restore", "reset"]) == false)
        if wantsRestore {
            scopes.append(.restoreAll)
        }
        if words.contains("duplicate") || words.contains("duplicates") {
            scopes.append(.duplicates)
        }
        if words.contains("python") || words.contains("pycache") {
            scopes.append(.pythonCaches)
        }
        if words.contains("node") || words.contains("npm") || lowered.contains("node_modules") {
            scopes.append(.nodeModules)
        }
        if words.contains("docker") {
            scopes.append(.docker)
        }
        if words.contains("brew") || words.contains("homebrew") {
            scopes.append(.homebrew)
        }
        if words.contains("cache") || words.contains("caches") || words.contains("temporary") || words.contains("temp") {
            scopes.append(.caches)
        }
        if words.contains("log") || words.contains("logs") {
            scopes.append(.logs)
        }
        if let days = olderThanDays(in: lowered) {
            scopes.append(.olderThan(days: days))
        } else if words.contains("old") && (words.contains("download") || words.contains("downloads") || words.contains("installer") || words.contains("installers")) {
            scopes.append(.oldDownloads(days: 30))
        }
        if words.isDisjoint(with: ["download", "downloads"]) == false, !scopes.contains(where: { if case .oldDownloads = $0 { return true }; return false }) {
            scopes.append(.downloads)
        }
        if words.contains("big") || words.contains("large") {
            scopes.append(.largerThan(bytes: lowered.contains("file") || lowered.contains("files") ? 1_000_000_000 : 100_000_000))
        }
        if words.isDisjoint(with: ["project", "projects", "developer", "dev"]) == false {
            scopes.append(.developerArtifacts)
        }
        if words.contains("safe") || words.contains("conservative") {
            scopes.append(.safeOnly)
        }
        if scopes.isEmpty {
            scopes = [.all]
        }
        return PlanIntent(action: action, scopes: scopes)
    }

    private static func olderThanDays(in lowered: String) -> Int? {
        guard lowered.contains("older than") || lowered.contains("old files") || lowered.contains("older") else {
            return nil
        }
        if let range = lowered.range(of: #"(\d+)\s*days?"#, options: .regularExpression),
           let days = Int(lowered[range].filter(\.isNumber)) {
            return days
        }
        return lowered.contains("older than") || lowered.contains("old files") ? 30 : nil
    }
}
