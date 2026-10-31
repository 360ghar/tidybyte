import XCTest
@testable import MacOSCleanerCore

/// Deep uninstaller matching on a fixture home and fixture /Library. Nothing
/// outside the temp directory is read.
final class DeepUninstallTests: XCTestCase {
    func testFootprintTiersAndLookAlikes() async throws {
        let root = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let system = root.appendingPathComponent("Library")
        let app = root.appendingPathComponent("Applications/X App.app")
        try make(app.appendingPathComponent("Contents/MacOS/x"))

        try make(home.appendingPathComponent("Library/Caches/com.x.app/blob"))
        try make(home.appendingPathComponent("Library/Preferences/com.x.app.plist"))
        try make(home.appendingPathComponent("Library/Preferences/com.x.app.helper.plist"))
        try make(home.appendingPathComponent("Library/Application Support/X App/data"))
        try make(home.appendingPathComponent("Library/Application Support/X App Pro/data"))
        let container = home.appendingPathComponent("Library/Containers/\(UUID().uuidString)")
        try make(container.appendingPathComponent("Data/file"))
        try plist(["MCMMetadataIdentifier": "com.x.app"], at: container.appendingPathComponent(
            ".com.apple.containermanagerd.metadata.plist"))
        try plist(["Label": "com.x.app.agent"], at: home.appendingPathComponent(
            "Library/LaunchAgents/com.x.app.agent.plist"))
        let helper = system.appendingPathComponent("PrivilegedHelperTools/com.vendor.updater")
        try make(helper)
        try plist(
            ["Label": "com.vendor.updater", "Program": helper.path, "AssociatedBundleIdentifiers": "com.x.app"],
            at: system.appendingPathComponent("LaunchDaemons/com.vendor.updater.plist"))
        try plist(
            ["Label": "com.unrelated", "Program": "/usr/local/bin/tool"],
            at: system.appendingPathComponent("LaunchDaemons/com.unrelated.plist"))

        // An openable ~/Library/Mail reads as Full Disk Access, which container metadata needs.
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Mail"), withIntermediateDirectories: true)
        let service = ApplicationFootprintService(
            homeDirectoryOverride: home, systemLibraryOverride: system, installedBundles: [])
        let target = InstalledApplication(
            id: "com.x.app", name: "X App", bundleURL: app, bundleIdentifier: "com.x.app", bundleSizeBytes: 0)
        let items = await service.footprintItems(for: target)
        let confidence = Dictionary(items.map { ($0.url.lastPathComponent, $0.confidence) }, uniquingKeysWith: max)

        XCTAssertEqual(confidence["com.x.app"], .certain)
        XCTAssertEqual(confidence["com.x.app.plist"], .certain)
        XCTAssertEqual(confidence["com.x.app.helper.plist"], .likely)
        XCTAssertEqual(confidence["X App"], .likely)
        XCTAssertEqual(confidence[container.lastPathComponent], .certain, "Container metadata names the app")
        XCTAssertEqual(confidence["com.x.app.agent.plist"], .certain)
        XCTAssertEqual(confidence["com.vendor.updater.plist"], .certain, "Daemon associated with the app")
        XCTAssertEqual(confidence["com.vendor.updater"], .certain, "Helper started by that daemon")
        XCTAssertNil(confidence["X App Pro"], "A look-alike name must never match")
        XCTAssertNil(confidence["com.unrelated.plist"])
        XCTAssertTrue(items.allSatisfy { !$0.reason.isEmpty })
    }

    func testDataOtherInstalledAppsUseIsNeverSure() async throws {
        let root = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let system = root.appendingPathComponent("Library")
        let app = root.appendingPathComponent("Applications/X App.app")
        try make(app.appendingPathComponent("Contents/MacOS/x"))
        let canary = root.appendingPathComponent("Applications/X Canary.app")
        try plist(["CFBundleIdentifier": "com.x.app.canary"], at: canary.appendingPathComponent("Contents/Info.plist"))
        let other = root.appendingPathComponent("Applications/Other.app")
        try plist(["CFBundleIdentifier": "com.other.app"], at: other.appendingPathComponent("Contents/Info.plist"))

        try make(home.appendingPathComponent("Library/Caches/com.x.app.canary/blob"))
        try make(home.appendingPathComponent("Library/Caches/com.x.app.helper/blob"))
        let helper = system.appendingPathComponent("PrivilegedHelperTools/com.vendor.updater")
        try make(helper)
        try plist(
            ["Label": "com.vendor.updater", "Program": helper.path,
                "AssociatedBundleIdentifiers": ["com.x.app", "com.other.app"]],
            at: system.appendingPathComponent("LaunchDaemons/com.vendor.updater.plist"))
        // Without Full Disk Access, container metadata is not read.
        let container = home.appendingPathComponent("Library/Containers/\(UUID().uuidString)")
        try plist(["MCMMetadataIdentifier": "com.x.app"], at: container.appendingPathComponent(
            ".com.apple.containermanagerd.metadata.plist"))

        let service = ApplicationFootprintService(
            homeDirectoryOverride: home, systemLibraryOverride: system, installedBundles: [canary, other])
        let target = InstalledApplication(
            id: "com.x.app", name: "X App", bundleURL: app, bundleIdentifier: "com.x.app", bundleSizeBytes: 0)
        let confidence = Dictionary(
            await service.footprintItems(for: target).map { ($0.url.lastPathComponent, $0.confidence) },
            uniquingKeysWith: max)

        XCTAssertNil(confidence["com.x.app.canary"], "Belongs to the installed Canary app")
        XCTAssertEqual(confidence["com.x.app.helper"], .likely)
        XCTAssertEqual(confidence["com.vendor.updater.plist"], .possible, "Another installed app uses the daemon")
        XCTAssertEqual(confidence["com.vendor.updater"], .possible)
        XCTAssertNil(confidence[container.lastPathComponent])

        // An app without a bundle ID never claims a container that has no metadata.
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Mail"), withIntermediateDirectories: true)
        let bare = home.appendingPathComponent("Library/Containers/\(UUID().uuidString)")
        try make(bare.appendingPathComponent("Data/file"))
        let unnamed = InstalledApplication(
            id: "path:x", name: "Unnamed", bundleURL: app, bundleIdentifier: nil, bundleSizeBytes: 0)
        let unnamedItems = await service.footprintItems(for: unnamed)
        XCTAssertFalse(unnamedItems.contains { $0.url.lastPathComponent == bare.lastPathComponent })
    }

    private func make(_ file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
    }

    private func plist(_ value: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        try data.write(to: url)
    }
}
