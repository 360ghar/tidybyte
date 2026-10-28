import Foundation
@testable import MacOSCleanerCore
import XCTest

final class MoCleanScannerTests: XCTestCase {
    private func makeTempHome() throws -> URL {
        try UserStoryFixtures.makeTemporaryDirectory(named: "MoCleanHome")
    }

    private func makeScanner(home: URL, installed: Set<String>? = []) -> MoCleanScanner {
        let index = installed.map { InstalledAppIndex(bundleIDs: $0) }
        return MoCleanScanner(homeDirectoryOverride: home, installedApps: { index })
    }

    /// Marks a fixture and its direct children as untouched for `days`.
    private func age(_ url: URL, days: Double = 45) throws {
        let date = Date().addingTimeInterval(-days * 86_400)
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for item in children + [url] {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: item.path)
        }
    }

    // MARK: - Cache-style sections

    func testBrowsersSectionSurfacesChromeCacheAsBrowserCacheCategory() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let caches = home.appendingPathComponent("Library/Caches/Google/Chrome/Default/Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        _ = try UserStoryFixtures.writeFile("Library/Caches/Google/Chrome/Default/Cache/blob.dat", in: home, data: Data(repeating: 1, count: 2_000_000))

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .browsers, sessionID: "scan")

        XCTAssertFalse(result.findings.isEmpty, "Browsers section should surface Chrome cache findings.")
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .browserCache })
        XCTAssertTrue(result.recommendations.allSatisfy { $0.actionType == .moveToTrash })
        XCTAssertGreaterThan(result.findings.reduce(Int64(0)) { $0 + $1.bytesReclaimable }, 0)
    }

    func testDeveloperToolsSectionSurfacesNpmAndBunCaches() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile("Library/Caches/Homebrew/brew.bin", in: home, data: Data(repeating: 1, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile(".bun/install/cache/pkg.tar", in: home, data: Data(repeating: 2, count: 2_000_000))

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .developerTools, sessionID: "scan")

        XCTAssertFalse(result.findings.isEmpty)
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .developerToolCache })
        XCTAssertTrue(result.recommendations.allSatisfy { $0.actionType == .moveToTrash })
    }

    func testUserEssentialsSectionSurfacesUserAppCacheAndLogs() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile("Library/Caches/com.example.app/cache.bin", in: home, data: Data(repeating: 1, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile("Library/Logs/com.example.app/run.log", in: home, data: Data(repeating: 2, count: 2_000_000))

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .userEssentials, sessionID: "scan")

        XCTAssertFalse(result.findings.isEmpty)
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .userEssentials })
    }

    // MARK: - Large files

    func testLargeFilesSectionSurfacesOnlyFilesOverOneGBAsInspectOnly() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // 1.5 GB sparse file: reports the full logical size through attributes
        // while occupying ~0 real disk blocks (the scanner only reads size).
        let big = try UserStoryFixtures.writeFile("Downloads/big.mov", in: home, data: Data("x".utf8))
        try TestFileFixtures.makeSparseFile(at: big, logicalSize: 1_500_000_000)
        // Small file that should be ignored
        _ = try UserStoryFixtures.writeFile("Downloads/small.txt", in: home, data: Data("tiny".utf8))

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .largeFiles, sessionID: "scan")

        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(result.findings.first?.category, .largeFileReview)
        XCTAssertEqual(result.recommendations.first?.actionType, .inspectOnly)
        XCTAssertEqual(result.findings.first?.bytesReclaimable, 1_500_000_000)
        XCTAssertTrue(result.files.contains { $0.url == big.standardizedFileURL })
    }

    // MARK: - Uninstalled app data

    func testUninstalledAppDataSurfacesOnlyOldDataOfMissingApps() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let library = home.appendingPathComponent("Library")
        for path in ["HTTPStorages/com.removed.tool/blob", "Application Support/com.removed.tool/db",
            "HTTPStorages/com.installed.app/data", "Caches/com.installed.app.helper/cache",
            "Caches/com.young.tool/cache", "Caches/com.installed.licensing/cache", "Caches/com.deep.tool/a/b/new"] {
            _ = try UserStoryFixtures.writeFile("Library/" + path, in: home, data: Data(repeating: 1, count: 4_096))
        }
        // Same vendor as an installed app; a file deep inside changed recently.
        for path in ["HTTPStorages/com.removed.tool", "Application Support/com.removed.tool",
            "HTTPStorages/com.installed.app", "Caches/com.installed.app.helper",
            "Caches/com.installed.licensing", "Caches/com.deep.tool"] {
            try age(library.appendingPathComponent(path))
        }

        let result = await makeScanner(home: home, installed: ["com.installed.app"])
            .scan(section: .uninstalledAppData, sessionID: "scan")

        XCTAssertEqual(result.findings.map { $0.evidence["bundle_id"] }, ["com.removed.tool"])
        XCTAssertEqual(result.findings.first?.targetFileIDs.count, 2, "One finding groups every folder of the app")
        XCTAssertEqual(result.findings.first?.category, .uninstalledAppData)
    }

    func testOrphanDetectionFailsClosedWithoutInventory() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile("Library/HTTPStorages/com.removed.tool/blob", in: home)
        try age(home.appendingPathComponent("Library/HTTPStorages/com.removed.tool"))
        let result = await makeScanner(home: home, installed: nil).scan(section: .uninstalledAppData, sessionID: "scan")
        XCTAssertTrue(result.findings.isEmpty, "Unknown inventory means nothing may be called orphaned")
    }

    func testLaunchAgentWithMissingProgramIsAnOrphan() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let gone: [String: Any] = ["Label": "com.gone.updater", "ProgramArguments": ["/Applications/Gone.app/Contents/MacOS/updater"]]
        let present = ["Label": "com.present.agent", "Program": "/bin/ls"] as [String: Any]
        for (name, job) in [("com.gone.updater.plist", gone), ("com.present.agent.plist", present)] {
            let url = agents.appendingPathComponent(name)
            try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: url)
            try age(url)
        }
        let result = await makeScanner(home: home).scan(section: .uninstalledAppData, sessionID: "scan")
        XCTAssertEqual(result.findings.map { $0.evidence["bundle_id"] }, ["com.gone.updater"])
    }

    // MARK: - Safety

    func testProtectedFilesAreNeverSurfacedAsFindings() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // .env is a protected filename; place it inside a scanned cache root
        _ = try UserStoryFixtures.writeFile("Library/Caches/.env", in: home, data: Data("TOKEN=secret".utf8))
        _ = try UserStoryFixtures.writeFile("Library/Caches/real_cache.bin", in: home, data: Data(repeating: 1, count: 2_000_000))

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .userEssentials, sessionID: "scan")

        // The cache root finding targets the Caches directory, not the .env file.
        // No finding should reference the .env path as a target.
        let allTargetPaths = result.files.map(\.displayPath)
        XCTAssertFalse(allTargetPaths.contains { $0.hasSuffix("/.env") })
    }

    // MARK: - Inspect-only sections

    func testCloudStorageSectionUsesInspectOnlyAction() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile("Library/Caches/Google Drive/sync.bin", in: home, data: Data(repeating: 1, count: 2_000_000))

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .cloudStorage, sessionID: "scan")

        XCTAssertTrue(result.recommendations.allSatisfy { $0.actionType == .inspectOnly })
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .cloudStorageCache })
    }

    func testTimeMachineSnapshotsAreReviewOnly() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // Reads `tmutil listlocalsnapshotdates /` (read-only). A Mac without
        // snapshots yields no finding; any finding must be review-only.
        let result = await makeScanner(home: home).scan(section: .timeMachineBackups, sessionID: "scan")
        XCTAssertLessThanOrEqual(result.findings.count, 1)
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .timeMachineBackup })
        XCTAssertTrue(result.recommendations.allSatisfy { $0.actionType == .inspectOnly })
    }

    func testApplicationSupportSectionIsInspectOnlyToProtectAppData() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile("Library/Application Support/com.example.app/db.sqlite", in: home, data: Data(repeating: 1, count: 2_000_000))

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .applicationSupport, sessionID: "scan")

        // Application Support contains app data, not just caches — must be inspect-only.
        XCTAssertTrue(result.recommendations.allSatisfy { $0.actionType == .inspectOnly })
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .applicationSupportCache })
    }

    func testSandboxedAppCachesSectionIsInspectOnlyToProtectContainers() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile("Library/Containers/com.example.app/Data/Library/Caches/blob.bin", in: home, data: Data(repeating: 1, count: 2_000_000))
        // Containers are read only with Full Disk Access; an openable ~/Library/Mail reads as granted.
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Mail"), withIntermediateDirectories: true)

        let scanner = makeScanner(home: home)
        let result = await scanner.scan(section: .sandboxedAppCaches, sessionID: "scan")

        // Containers hold sandboxed app data — must be inspect-only.
        XCTAssertFalse(result.recommendations.isEmpty)
        XCTAssertTrue(result.recommendations.allSatisfy { $0.actionType == .inspectOnly })
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .sandboxedAppCache })
    }

    // MARK: - Section registry

    func testEverySystemCleanSectionMapsToScanModeAndCategory() {
        for section in MoCleanScanner.SystemCleanSection.allCases {
            let mode = ScanMode(rawValue: section.rawValue)
            XCTAssertNotNil(mode, "Section \(section.rawValue) has no matching ScanMode case.")
            XCTAssertEqual(mode?.systemCleanSection, section)
            XCTAssertNotNil(section.findingCategory)
        }
    }

    func testEverySystemCleanScanModeResolvesKnownPaths() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for section in MoCleanScanner.SystemCleanSection.allCases {
            let paths = section.knownPaths(home: home)
            XCTAssertFalse(paths.isEmpty, "Section \(section.rawValue) has no known paths.")
        }
    }

    // MARK: - Orchestrator integration

    func testOrchestratorDeveloperToolsScanProducesReviewablePlan() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try UserStoryFixtures.writeFile(".bun/install/cache/pkg.tar", in: home, data: Data(repeating: 1, count: 2_000_000))
        _ = try UserStoryFixtures.writeFile("Library/Caches/Homebrew/brew.bin", in: home, data: Data(repeating: 2, count: 2_000_000))

        let store = try SQLiteStore.inMemory()
        let memory = MemoryEngine(store: store)
        let permissionManager = PermissionManager(homeDirectoryOverride: home)
        let moCleanScanner = MoCleanScanner(homeDirectoryOverride: home)
        let orchestrator = ScanOrchestrator(
            store: store,
            permissionManager: permissionManager,
            moCleanScanner: moCleanScanner,
            memory: memory
        )

        let (outcome, plan) = try await orchestrator.scan(
            mode: .developerTools,
            selectedFolders: [],
            providerSettings: ProviderSettings(privacyMode: .localOnly),
            includeAI: false,
            posture: .conservative
        )

        XCTAssertEqual(outcome.session.status, .completed)
        XCTAssertEqual(outcome.session.scanType, .developerTools)
        XCTAssertTrue(outcome.findings.contains { $0.category == .developerToolCache })
        XCTAssertGreaterThan(plan.estimatedReclaimableBytes, 0)
        XCTAssertTrue(plan.actions.allSatisfy { $0.userDecision == .undecided && $0.status == .proposed })
        // System-clean sections skip duplicate/project/package stages.
        XCTAssertTrue(outcome.projects.isEmpty)
        XCTAssertTrue(outcome.packageCandidates.isEmpty)
    }
}
