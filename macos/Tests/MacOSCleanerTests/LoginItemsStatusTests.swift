import Darwin
import XCTest
@testable import MacOSCleanerCore

final class LoginItemsStatusTests: XCTestCase {
    func testLaunchItemsSkipAppleAndOnlyUserAgentsAreRemovable() throws {
        let root = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let library = root.appendingPathComponent("Library")
        try write(
            ["Label": "com.vendor.agent", "Program": "/Applications/Vendor.app/Contents/MacOS/agent"],
            to: home.appendingPathComponent("Library/LaunchAgents/com.vendor.agent.plist"))
        try write(
            ["Label": "com.apple.thing", "Program": "/usr/libexec/thing"],
            to: home.appendingPathComponent("Library/LaunchAgents/com.apple.thing.plist"))
        try write(
            ["Label": "com.vendor.daemon", "ProgramArguments": ["/bin/ls", "-l"]],
            to: library.appendingPathComponent("LaunchDaemons/com.vendor.daemon.plist"))

        let items = LaunchItems.list(home: home, systemLibrary: library)

        XCTAssertEqual(items.map(\.label), ["com.vendor.agent", "com.vendor.daemon"])
        let agent = try XCTUnwrap(items.first { $0.label == "com.vendor.agent" })
        XCTAssertTrue(agent.canRemove)
        XCTAssertTrue(agent.isProgramMissing)
        XCTAssertEqual(agent.appBundle?.lastPathComponent, "Vendor.app")
        let daemon = try XCTUnwrap(items.first { $0.label == "com.vendor.daemon" })
        XCTAssertFalse(daemon.canRemove, "System daemons are managed in System Settings")
        XCTAssertFalse(daemon.isProgramMissing)
    }

    func testMemoryArithmeticMatchesActivityMonitor() {
        var stats = vm_statistics64()
        stats.internal_page_count = 1_000
        stats.purgeable_count = 100
        stats.wire_count = 200
        stats.compressor_page_count = 50
        stats.external_page_count = 300
        let snapshot = SystemStatus.snapshot(
            stats, pageSize: 16_384, totalBytes: 16 * 1_073_741_824, swapUsedBytes: 0, pressureLevel: 2)
        XCTAssertEqual(snapshot.appBytes, 900 * 16_384)
        XCTAssertEqual(snapshot.usedBytes, (900 + 200 + 50) * 16_384)
        XCTAssertEqual(snapshot.cachedBytes, 400 * 16_384)
        XCTAssertEqual(snapshot.pressure, .warning)
        XCTAssertNotNil(SystemStatus.memory())
    }

    private func write(_ job: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: url)
    }
}
