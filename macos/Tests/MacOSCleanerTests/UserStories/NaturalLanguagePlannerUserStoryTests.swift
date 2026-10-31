import Foundation
@testable import MacOSCleanerCore
import XCTest

final class NaturalLanguagePlannerUserStoryTests: XCTestCase {
    func testCacheCommandShowsOnlyCacheActions() async {
        let scenario = makeScenario()
        let planner = PlannerAgent()

        let updated = await planner.planForNaturalLanguageCommand(
            "cache",
            existingPlan: scenario.plan,
            filesByID: scenario.filesByID
        )

        XCTAssertEqual(updated.actions.map(\.id), ["cache-action"])
        XCTAssertEqual(updated.estimatedFilesAffected, 1)
        XCTAssertEqual(updated.estimatedReclaimableBytes, 2_000_000)
        XCTAssertEqual(updated.riskBreakdown, [.low: 1])
    }

    func testSafeCachesCommandCombinesCacheAndLowRiskFilters() async {
        let scenario = makeScenario(includeMediumCache: true)
        let planner = PlannerAgent()

        let updated = await planner.planForNaturalLanguageCommand(
            "safe caches",
            existingPlan: scenario.plan,
            filesByID: scenario.filesByID
        )

        XCTAssertEqual(updated.actions.map(\.id), ["cache-action"])
        XCTAssertEqual(updated.summary, "Targeted safe plan: caches and temporary files.")
        XCTAssertEqual(updated.estimatedFilesAffected, 1)
        XCTAssertEqual(updated.estimatedReclaimableBytes, 2_000_000)
        XCTAssertEqual(updated.riskBreakdown, [.low: 1])
    }

    func testSuccessiveCommandsReapplyAgainstOriginalActions() async {
        let scenario = makeScenario()
        let planner = PlannerAgent()

        let safeOnly = await planner.planForNaturalLanguageCommand(
            "safe",
            existingPlan: scenario.plan,
            filesByID: scenario.filesByID
        )
        let cacheOnly = await planner.planForNaturalLanguageCommand(
            "cache",
            existingPlan: safeOnly,
            filesByID: scenario.filesByID
        )

        XCTAssertEqual(safeOnly.actions.map(\.id), ["duplicate-action", "cache-action", "installer-action"])
        XCTAssertEqual(cacheOnly.actions.map(\.id), ["cache-action"])
        XCTAssertEqual(cacheOnly.originalActions?.count, scenario.plan.actions.count)
    }

    private func makeScenario(includeMediumCache: Bool = false) -> (plan: Plan, filesByID: [String: FileRecord]) {
        let duplicate = makeFile(id: "duplicate", path: "/tmp/Downloads/duplicate.txt", bytes: 22)
        let cache = makeFile(id: "cache", path: "/tmp/Caches/App/cache.bin", bytes: 2_000_000)
        let installer = makeFile(id: "installer", path: "/tmp/Downloads/old-installer.dmg", bytes: 8)
        let mediumCache = makeFile(id: "medium-cache", path: "/tmp/Caches/App/build-cache.bin", bytes: 3_000_000)

        var actions = [
            makeAction(
                id: "duplicate-action",
                targetID: duplicate.id,
                risk: .low,
                reason: "These files have the same size and content hash."
            ),
            makeAction(
                id: "cache-action",
                targetID: cache.id,
                risk: .low,
                reason: "Caches and logs are usually rebuildable."
            ),
            makeAction(
                id: "installer-action",
                targetID: installer.id,
                risk: .low,
                reason: "The file is an old downloaded installer."
            )
        ]
        if includeMediumCache {
            actions.append(
                makeAction(
                    id: "medium-cache-action",
                    targetID: mediumCache.id,
                    risk: .medium,
                    reason: "A cache that still needs manual review."
                )
            )
        }

        let files = [duplicate, cache, installer, mediumCache]
        let plan = Plan(
            id: "plan",
            scanSessionID: "scan",
            createdAt: Date(),
            status: .proposed,
            summary: "fixture plan",
            estimatedReclaimableBytes: files.reduce(Int64(0)) { $0 + $1.sizeBytes },
            estimatedFilesAffected: files.count,
            riskBreakdown: Dictionary(grouping: actions, by: \.risk).mapValues(\.count),
            actions: actions
        )
        return (plan, Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) }))
    }

    private func makeFile(id: String, path: String, bytes: Int64) -> FileRecord {
        let url = URL(fileURLWithPath: path)
        return FileRecord(
            id: id,
            scanSessionID: "scan",
            source: .local,
            url: url,
            displayPath: url.path,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            utiDescription: nil,
            kind: .regularFile,
            sizeBytes: bytes,
            createdAt: nil,
            modifiedAt: nil,
            lastOpenedAt: nil,
            owner: nil,
            permissions: nil,
            isSymlink: false,
            symlinkTarget: nil,
            isPackage: false,
            isCloudPlaceholder: false,
            cloudProvider: nil,
            finderTags: [],
            spotlightMetadata: [:],
            riskFlags: [],
            identity: FileIdentity(deviceIdentifier: nil, inodeIdentifier: nil, resourceIdentifier: nil),
            capabilities: [.canMove, .canTrash, .canRestore]
        )
    }

    private func makeAction(id: String, targetID: String, risk: RiskLevel, reason: String) -> PlannedAction {
        PlannedAction(
            id: id,
            planID: "plan",
            actionType: .moveToTrash,
            targets: [targetID],
            destination: nil,
            status: .proposed,
            risk: risk,
            confidence: 0.9,
            reason: reason,
            userDecision: .undecided,
            executedAt: nil,
            findingID: id
        )
    }
}
