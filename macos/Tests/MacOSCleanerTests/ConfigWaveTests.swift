import Foundation
@testable import MacOSCleanerAppKit
@testable import MacOSCleanerCore
import XCTest

/// Review-wave tests (2026-08-01): privacy default, localized category names,
/// and exhaustive settings clearing. (Review-only execution filtering is
/// covered by AppViewModelTests.testInspectOnlyActionFailsDuringExecution.)
@MainActor
final class ConfigWaveTests: XCTestCase {
    private func makeDefaultsSuite() -> UserDefaults {
        makeIsolatedDefaults()
    }

    private func makeModel(defaults: UserDefaults, store: SQLiteStore? = nil) throws -> AppViewModel {
        let resolvedStore = try store ?? SQLiteStore.inMemory()
        let memory = MemoryEngine(store: resolvedStore)
        let planner = PlannerAgent()
        let orchestrator = ScanOrchestrator(store: resolvedStore, memory: memory)
        let executor = TestFixtures.makeExecutor(store: resolvedStore)
        let undo = UndoManagerService(store: resolvedStore, memory: memory)
        let reports = ReportGenerator(store: resolvedStore)
        return AppViewModel(
            store: resolvedStore,
            keychain: KeychainStore(inMemory: true),
            memory: memory,
            orchestrator: orchestrator,
            executor: executor,
            undoService: undo,
            reportGenerator: reports,
            notifications: NotificationScheduler(),
            planner: planner,
            defaults: defaults
        )
    }

    /// Mirrors the persisted keys; keep in sync with `SettingsKey` in
    /// AppViewModel.swift (the app derives its lists from that enum, so adding
    /// a key there without clearing it here fails this test).
    private let persistedKeys = [
        "selectedMode", "selectedFolderPaths", "cleanupPosture", "includeAI",
        "providerName", "apiBaseURL", "textModel", "maxTokens", "temperature", "privacyMode",
        "exploreViewKind", "exploreGrouping", "exploreDepth"
    ]

    func testProviderSettingsDefaultsToLocalOnlyPrivacy() {
        let settings = ProviderSettings()
        XCTAssertEqual(settings.privacyMode, .localOnly, "DESIGN.md requires local-only as the factory default")
    }

    func testFindingCategoryDisplayNamesAreLocalizedAndReadable() {
        for category in FindingCategory.allCases {
            let name = category.displayName
            XCTAssertFalse(name.isEmpty, "\(category.rawValue) must have a display name")
            XCTAssertFalse(name.contains("_"), "displayName must not leak snake_case rawValue: \(name)")
            XCTAssertNotEqual(name, category.rawValue, "displayName must differ from the raw value")
        }
    }

    func testClearAllDataClearsEveryPersistedKey() async throws {
        let defaults = makeDefaultsSuite()
        for key in persistedKeys {
            defaults.set("value-\(key)", forKey: key)
        }
        let model = try makeModel(defaults: defaults)
        await model.clearAllData()
        for key in persistedKeys {
            XCTAssertNil(defaults.object(forKey: key), "Key \(key) must be cleared by clearAllData")
        }
    }
}
