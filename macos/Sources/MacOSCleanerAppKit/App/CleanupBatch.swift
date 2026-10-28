import Foundation
import MacOSCleanerCore

/// The confirmation and executor share this fixed list, including its scan and settings.
struct CleanupBatch: Identifiable {
    let id = UUID()
    let generation: UUID
    let scopeID: String
    let tool: CleanupTool
    let items: [ReviewItem]
    let retained: [ReviewItem]
    let settings: CleanupSettings
}

extension CleanupModel {
    func makeBatch(items: [ReviewItem], tool: CleanupTool) -> CleanupBatch? {
        guard let result, result.isFresh, result.scopeID == scope.id else { return nil }
        let proposed = Set(items.map(\.reviewKey))
        let candidates = self.items(for: tool).filter {
            proposed.contains($0.reviewKey) && $0.canChange && (!tool.isCompression || $0.canAnalyze)
        }
        let ids = Set(candidates.map(\.id))
        let safe = tool.isCompression ? ids : MediaAnalysisService.safeSelection(ids, groups: result.groups)
        let selected = candidates.filter { safe.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        let affected = result.groups.filter {
            $0.tool == .formatPairs && !$0.memberIDs.allSatisfy { !safe.contains($0) }
        }
        let retainedIDs = Set(affected.flatMap(\.memberIDs)).subtracting(safe)
        return CleanupBatch(
            generation: result.generation, scopeID: scope.id, tool: tool, items: selected,
            retained: tool == .formatPairs ? result.items.filter { retainedIDs.contains($0.id) } : [],
            settings: settings)
    }

    func validate(_ batch: CleanupBatch) -> Bool {
        guard let result, result.isFresh, result.scopeID == scope.id, batch.scopeID == scope.id,
            result.generation == batch.generation, !batch.items.isEmpty,
            result.settingsVersion == batch.settings.analysisVersion
        else {
            error = String(localized: "Scan results changed. Review the selected items again before continuing.")
            return false
        }
        let available = Dictionary(result.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(batch.items.map(\.id))
        guard
            batch.items.allSatisfy({
                available[$0.id]?.reviewKey == $0.reviewKey && available[$0.id]?.source == $0.source && $0.canChange
            }), batch.tool.isCompression || MediaAnalysisService.safeSelection(ids, groups: result.groups) == ids
        else {
            error = String(localized: "The selection changed. Review it again before continuing.")
            return false
        }
        return true
    }
}
