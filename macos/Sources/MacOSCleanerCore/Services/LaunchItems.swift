import Foundation
import ServiceManagement

/// One launchd job definition from a LaunchAgents or LaunchDaemons folder.
public struct LaunchItem: Identifiable, Sendable, Hashable {
    public enum Domain: String, Sendable {
        case userAgent, systemAgent, systemDaemon

        public var displayName: String {
            switch self {
            case .userAgent: String(localized: "Agent (this user)", comment: "Launch item kind")
            case .systemAgent: String(localized: "Agent (all users)", comment: "Launch item kind")
            case .systemDaemon: String(localized: "Daemon", comment: "Launch item kind")
            }
        }
    }

    public var id: String { url.path }
    public let url: URL
    public let label: String
    public let program: String?
    public let domain: Domain
    public let isProgramMissing: Bool
    public let isEnabled: Bool?

    public var isApple: Bool { label.hasPrefix("com.apple.") }
    /// Only the user's own, non-Apple agents can be removed here; the rest
    /// belong in System Settings › Login Items.
    public var canRemove: Bool { domain == .userAgent && !isApple }
    /// The app bundle that owns the program, if the program lives in one.
    public var appBundle: URL? {
        guard let program, let range = program.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(program[..<range.lowerBound]) + ".app")
    }
}

public enum LaunchItems {
    /// Every job plist in the three launchd folders, Apple items excluded.
    public static func list(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library", isDirectory: true)
    ) -> [LaunchItem] {
        let folders: [(LaunchItem.Domain, URL)] = [
            (.userAgent, home.appendingPathComponent("Library/LaunchAgents")),
            (.systemAgent, systemLibrary.appendingPathComponent("LaunchAgents")),
            (.systemDaemon, systemLibrary.appendingPathComponent("LaunchDaemons"))
        ]
        return folders.flatMap { domain, folder in
            let plists = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return plists.filter { $0.pathExtension == "plist" }.compactMap { item(at: $0, domain: domain) }
        }
        .filter { !$0.isApple }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static func item(at url: URL, domain: LaunchItem.Domain) -> LaunchItem? {
        guard let job = NSDictionary(contentsOf: url) as? [String: Any], let label = job["Label"] as? String else {
            return nil
        }
        let program = (job["Program"] as? String) ?? (job["ProgramArguments"] as? [String])?.first
        let missing = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false
        let status = SMAppService.statusForLegacyPlist(at: url)
        return LaunchItem(
            url: url, label: label, program: program, domain: domain, isProgramMissing: missing,
            isEnabled: status == .notFound ? nil : status == .enabled)
    }
}
