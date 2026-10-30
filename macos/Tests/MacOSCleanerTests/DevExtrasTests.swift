import XCTest
@testable import MacOSCleanerCore

/// Parsers for tool output. Real tools never run here.
final class DevExtrasTests: XCTestCase {
    func testBrewDryRunSize() {
        let output = "Would remove: /opt/homebrew/Cellar/foo/1.0 (12 files)\n"
            + "==> This operation would free approximately 1.5GB of disk space."
        XCTAssertEqual(PackageManagerScanner.brewFreedBytes(output), 1_610_612_736, "1.5 GB in powers of 1024")
        XCTAssertNil(PackageManagerScanner.brewFreedBytes("Nothing to clean"))
    }

    func testUnavailableSimulatorCount() {
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"name":"iPhone 15"},{"name":"iPad"}],"x":[]}}"#
        XCTAssertEqual(PackageManagerScanner.unavailableSimulatorCount(json), 2)
        XCTAssertEqual(PackageManagerScanner.unavailableSimulatorCount("not json"), 0)
    }

    func testDeviceSupportKeepsNewestSystemVersion() {
        let base = URL(fileURLWithPath: "/tmp/iOS DeviceSupport")
        let names = ["iPhone14,2 26.5 (23F77)", "17.2 (21C52)", "iPhone12,1 18.1 (22B83)", "Notes"]
        let older = MoCleanScanner.olderDeviceSupport(names.map { base.appendingPathComponent($0) })
        XCTAssertEqual(Set(older.map(\.lastPathComponent)), ["17.2 (21C52)", "iPhone12,1 18.1 (22B83)"])
    }

    func testLocalSnapshotDates() {
        let output = "Snapshot dates for disk /:\n2026-10-28-101530\n2026-10-27-091500\n"
        XCTAssertEqual(MoCleanScanner.localSnapshotDates(output), ["2026-10-27-091500", "2026-10-28-101530"])
    }

    func testPackageCommandWaitsForBlockingTool() async {
        let missing = await ActionExecutor.firstRunning(["tidybyte-no-such-process"])
        XCTAssertNil(missing)
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["5"]
        try? sleeper.run()
        defer { sleeper.terminate() }
        let running = await ActionExecutor.firstRunning(["sleep"])
        XCTAssertEqual(running, "sleep")
    }

    /// Records only; the rule engine never reads these paths.
    func testInstallersOnTheDesktopAreOldInstallers() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var records: [FileRecord] = []
        for (id, path) in [("desktop", "Desktop/Tool.dmg"), ("downloads", "Downloads/Tool.dmg"),
            ("project", "Projects/documents/Tool.dmg")] {
            var record = TestFixtures.makeFileRecord(
                id: id, path: home.appendingPathComponent(path).path, sizeBytes: 50_000_000)
            record.modifiedAt = Date().addingTimeInterval(-60 * 86_400)
            records.append(record)
        }
        let (findings, recommendations) = try await CleanerRuleEngine().analyze(files: records, projects: [], sessionID: "s")
        let risk = { (id: String) in recommendations.first { $0.targetFileIDs == [id] }?.risk }
        XCTAssertEqual(findings.first { $0.targetFileIDs == ["desktop"] }?.category, .oldInstaller)
        XCTAssertEqual(risk("desktop"), .medium, "Bulk Approve Low Risk skips installers kept outside Downloads")
        XCTAssertEqual(risk("downloads"), .low)
        XCTAssertNil(risk("project"), "Only ~/Desktop and ~/Documents count, not any folder named documents")
    }
}
