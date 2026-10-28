import Foundation
import MacOSCleanerCore

/// Immutable approval summary. A changed plan requires a new confirmation.
struct ExecutionRequest: Identifiable {
    let id = UUID()
    let maximumRisk: RiskLevel
    let actions: [PlannedAction]
    let planSignature: Data
    let fileCount: Int
    let estimatedBytes: Int64
    let unresolvedTargetCount: Int
    /// Approved actions per sidebar row, for display only. The action list above
    /// is the execution contract.
    let areaCounts: [(area: AppDestination, count: Int)]

    var actionIDs: Set<String> { Set(actions.map(\.id)) }
    var isTrashOnly: Bool { actions.allSatisfy { $0.actionType == .moveToTrash } }
    var hasPackageCommands: Bool { actions.contains { $0.actionType == .runPackageManagerCleanup } }
    var confirmTitle: String {
        isTrashOnly ? String(localized: "Move to Trash") : String(localized: "Apply Changes")
    }
    var operationTypes: [ActionType] {
        ActionType.allCases.filter { type in actions.contains { $0.actionType == type } }
    }

    @MainActor
    init?(model: AppViewModel, maximumRisk: RiskLevel) {
        let actions = model.pendingExecutableActions(upTo: maximumRisk)
        guard !actions.isEmpty, let signature = model.executionPlanSignature else { return nil }
        self.maximumRisk = maximumRisk
        self.actions = actions
        planSignature = signature
        let fileActions = actions.filter { $0.actionType != .runPackageManagerCleanup }
        let targetIDs = Set(fileActions.flatMap(\.targets))
        fileCount = Set(targetIDs.compactMap { model.filesByID[$0]?.url.standardizedFileURL.path }).count
        unresolvedTargetCount = targetIDs.filter { model.filesByID[$0] == nil }.count
        estimatedBytes = Self.estimatedTrashBytes(actions: actions, files: Array(model.filesByID.values))
        let ids = Set(actions.map(\.id))
        areaCounts = AppDestination.allCases.compactMap { area in
            let count = model.actions(in: area).filter { ids.contains($0.id) }.count
            return count > 0 ? (area, count) : nil
        }
    }

    /// Directory aggregates and descendants can both be selected. Count each path once.
    static func estimatedTrashBytes(actions: [PlannedAction], files: [FileRecord]) -> Int64 {
        let byPath = Dictionary(
            files.map { ($0.url.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, second in first.sizeBytes >= second.sizeBytes ? first : second })
        let targetIDs = Set(actions.filter { $0.actionType == .moveToTrash }.flatMap(\.targets))
        let targetPaths = Set(files.filter { targetIDs.contains($0.id) }.map { $0.url.standardizedFileURL.path })
        let targets = targetPaths.compactMap { byPath[$0] }
            .sorted { $0.url.path.count < $1.url.path.count }
        let totals = ExploreSubtreeIndex.totals(files: Array(byPath.values))
        var coveredFolders: [String] = []
        var bytes: Int64 = 0
        for target in targets {
            let path = target.url.standardizedFileURL.path
            guard !coveredFolders.contains(where: { path.hasPrefix($0 + "/") }) else { continue }
            if target.kind == .directory || target.kind == .package {
                coveredFolders.append(path)
                bytes += max(target.sizeBytes, totals[path] ?? 0)
            } else {
                bytes += max(0, target.sizeBytes)
            }
        }
        return bytes
    }

    @MainActor
    func isCurrent(in model: AppViewModel) -> Bool {
        planSignature == model.executionPlanSignature && !model.isScanning && !model.isExecuting && !model.isPlanning
    }
}

extension AppViewModel {
    var executionPlanSignature: Data? {
        guard let plan else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(plan)
    }

    static func isSupportedOperation(_ type: ActionType) -> Bool {
        switch type {
        case .moveToTrash, .move, .rename, .tag, .createAlias, .createSymlink, .archive, .runPackageManagerCleanup, .cloneDeduplicate: true
        default: false
        }
    }

    func pendingExecutableActions(upTo maximumRisk: RiskLevel = .high) -> [PlannedAction] {
        approvedActions(for: maximumRisk).filter {
            $0.executedAt == nil && $0.status != .completed && $0.status != .failed
                && $0.risk != .forbidden && Self.isSupportedOperation($0.actionType)
        }
    }

    func actionMatchesSearch(_ action: PlannedAction) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || action.reason.localizedCaseInsensitiveContains(query)
            || action.actionType.displayName.localizedCaseInsensitiveContains(query)
            || action.targets.contains { filesByID[$0]?.displayPath.localizedCaseInsensitiveContains(query) == true }
    }
}
