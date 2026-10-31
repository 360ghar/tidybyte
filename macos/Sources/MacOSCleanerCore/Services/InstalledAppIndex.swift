import Foundation

/// Bundle IDs of every installed app, used to decide whether data named
/// after a bundle ID is orphaned. Built once per scan.
public struct InstalledAppIndex: Sendable {
    public var bundleIDs: Set<String>

    public init(bundleIDs: Set<String>) {
        self.bundleIDs = Set(bundleIDs.map { $0.lowercased() })
    }

    /// Helpers and extensions extend the main app's ID (com.x.app.helper),
    /// so a prefix relation in either direction counts as installed. Vendors
    /// share data across their apps (com.microsoft.office.licensingV2), so
    /// any installed app of the same vendor (com.microsoft) counts too.
    public func isInstalled(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        let vendor = id.split(separator: ".").prefix(2).joined(separator: ".") + "."
        return bundleIDs.contains(id)
            || bundleIDs.contains { id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") || $0.hasPrefix(vendor) }
    }

    /// Spotlight's list of application bundles plus the standard app folders.
    /// Nil when Spotlight indexing is off or the listing came back truncated:
    /// without a complete inventory no data may be called orphaned (fail
    /// closed — an app missing from a partial list must never be staged for
    /// deletion).
    public static func live(home: URL) async -> InstalledAppIndex? {
        let status = await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/mdutil"), arguments: ["-s", "/"], timeout: 10)
        guard status.exitCode == 0, status.stdout.contains("Indexing enabled") else { return nil }
        let found = await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/mdfind"),
            arguments: ["kMDItemContentType == 'com.apple.application-bundle'"], timeout: 30)
        guard found.exitCode == 0, !found.truncated else { return nil }
        let bundles = found.stdout.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            + standardBundles(home: home)
        return InstalledAppIndex(bundleIDs: Set(bundles.compactMap { Bundle(url: $0)?.bundleIdentifier }))
    }

    /// App bundles in the standard app folders. Fast; no Spotlight.
    public static func standardBundles(home: URL) -> [URL] {
        ["/Applications", "/Applications/Utilities", "/System/Applications",
            "/System/Applications/Utilities", home.appendingPathComponent("Applications").path].flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent($0) }
        }
    }

    /// True for names like `com.vendor.app`: three or more dot-separated parts,
    /// a lowercase first part, and not Apple's own namespace.
    public static func isThirdPartyBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }), !name.contains(" "),
            let first = parts.first, first.allSatisfy({ $0.isLowercase && $0.isLetter }) else { return false }
        return !name.lowercased().hasPrefix("com.apple.")
    }
}
