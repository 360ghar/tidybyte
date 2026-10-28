import Foundation

/// Outcome of asking the policy whether a filesystem location may be used
/// as a cleanup target or as an action destination.
public enum PolicyDecision: Sendable, Equatable {
    case allow
    case deny(reason: String)
}

public struct PathSafetyPolicy: Sendable {
    /// Lowercased by contract: path components are compared case-insensitively
    /// (APFS is case-insensitive by default), so "Keychains" and "KEYCHAINS"
    /// must both match.
    public let protectedDirectoryNames: Set<String> = [
        ".ssh", ".gnupg", ".aws", ".config", "keychains", "mobilesync", "mail",
        "passwords", "1password", "bitwarden", "keepass",
        ".git", ".svn", ".hg"
    ]

    /// Lowercased by contract — compared against `url.lastPathComponent.lowercased()`.
    public let protectedFileNames: Set<String> = [
        ".env", ".env.local", ".env.production", ".env.development", ".env.staging", ".env.test",
        "agents.md", "agents.override.md",
        "claude.md", "settings.json", "settings.local.json", "config.yaml",
        "id_rsa", "id_ed25519", "known_hosts"
    ]

    public let protectedExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "cer", "crt", "mobileprovision", "provisionprofile",
        "gpg", "pgp", "der", "jks", "keystore", "keychain", "keychain-db", "p8"
    ]

    /// Lowercased path fragments that hold irreplaceable developer state
    /// (Xcode team/signing data, simulator devices). Matched anywhere in a path.
    public let protectedPathFragments: [String] = [
        "/library/developer/xcode/userdata", "/library/developer/coresimulator/devices"
    ]

    public let sourceExtensions: Set<String> = [
        "swift", "py", "js", "jsx", "ts", "tsx", "java", "kt", "go", "rs", "c",
        "cc", "cpp", "h", "hpp", "m", "mm", "rb", "php", "cs", "scala", "sql",
        "md", "mdx", "html", "css", "scss", "json", "yaml", "yml", "toml"
    ]

    public let manifestNames: Set<String> = [
        "package.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "pyproject.toml",
        "requirements.txt", "poetry.lock", "uv.lock", "cargo.toml", "go.mod",
        "pom.xml", "build.gradle", "package.swift", "dockerfile", "docker-compose.yml",
        "makefile", "readme", "readme.md", "gemfile", "podfile"
    ]

    /// SIP-protected system paths — shared between riskFlags and shouldSkipTraversal.
    /// Includes firmlink/symlink aliases (/etc, /tmp → /private/...) because APFS
    /// presents them as top-level roots. Comparisons are lowercased (APFS is
    /// case-insensitive by default; "/SYSTEM/LIBRARY" must not bypass this list).
    ///
    /// Deliberately EXCLUDES /Library and /private/var: the deep-system,
    /// macOS-system-caches, and Apple-Silicon-update sections legitimately
    /// enumerate those trees as inspect-only review targets. Dangerous spots
    /// inside them (/Library/Keychains, ~/Library/MobileSync) are covered by
    /// protectedDirectoryNames instead.
    private static let sipProtectedPaths = [
        "/system", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/libexec",
        "/usr/lib", "/usr/share", "/private/etc", "/private/tmp",
        "/etc", "/tmp", "/home"
    ]

    /// Apple-managed per-user temp/cache space (DARWIN_USER_TEMP_DIR). Lives
    /// under /var(folders) but is NOT system software: sandboxed tooling,
    /// test fixtures, and temp files legitimately operate here, and the OS
    /// prunes it itself. Exempted from the SIP flag.
    private static let appleManagedTempPrefixes = ["/var/folders", "/private/var/folders"]

    private static func isAppleManagedTempSpace(_ path: String) -> Bool {
        appleManagedTempPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    public init() {}

    public func riskFlags(for url: URL, isDirectory: Bool) -> Set<RiskFlag> {
        var flags = Set<RiskFlag>()
        let name = url.lastPathComponent
        let standardized = url.standardizedFileURL
        let path = standardized.path.lowercased()
        let components = standardized.pathComponents.map { $0.lowercased() }

        if Self.sipProtectedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }),
           !Self.isAppleManagedTempSpace(path) {
            flags.insert(.sipProtectedSystemPath)
        }
        if components.contains(where: { protectedDirectoryNames.contains($0) })
            || protectedPathFragments.contains(where: { Self.path(path, contains: $0) }) {
            flags.insert(.protectedDirectory)
        }
        if protectedFileNames.contains(name.lowercased()) || name.lowercased().hasPrefix("com.apple.dt.") {
            flags.insert(.protectedFile)
        }
        if Self.path(path, contains: "/library/developer/xcode/archives") || url.pathExtension.lowercased() == "xcarchive" {
            flags.insert(.reviewOnly)
        }
        let fileExtension = url.pathExtension.lowercased()
        if protectedExtensions.contains(fileExtension) {
            flags.insert(.secretOrCertificate)
        }
        if manifestNames.contains(name.lowercased()) {
            flags.insert(.projectManifest)
        }
        if !isDirectory, sourceExtensions.contains(fileExtension) {
            flags.insert(.sourceOrConfig)
        }
        if cloudProvider(for: url) != nil {
            flags.insert(.cloudSyncedLocalPath)
        }
        if isCodingAgentConfigPath(url) {
            flags.insert(.codingAgentMemoryOrConfig)
        }
        if isInsideTrash(standardized) {
            flags.insert(.insideTrash)
        }
        return flags
    }

    /// True when `fragment` is a whole-component run inside `path` (both lowercased).
    private static func path(_ path: String, contains fragment: String) -> Bool {
        path.hasSuffix(fragment) || path.contains(fragment + "/")
    }

    /// True for anything under the user's Trash or any volume's `.Trashes`
    /// folder (`/Volumes/<disk>/.Trashes/<uid>/...`). Items already in the
    /// Trash must never be re-proposed for cleanup.
    func isInsideTrash(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        if components.contains(".trashes") {
            return true
        }
        let trashPath = Self.homeTrashPath
        let path = url.standardizedFileURL.path.lowercased()
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    private static let homeTrashPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".Trash", isDirectory: true)
        .standardizedFileURL.path.lowercased()

    public func isProtectedFromCleanup(_ record: FileRecord) -> Bool {
        !record.riskFlags.intersection(Self.allProtectionFlags).isEmpty
    }

    public func isProtectedFromCleanup(url: URL, isDirectory: Bool) -> Bool {
        let flags = riskFlags(for: url, isDirectory: isDirectory)
        return !flags.intersection(Self.allProtectionFlags).isEmpty
    }

    /// All risk flags that indicate a file should be protected from cleanup.
    private static let allProtectionFlags: Set<RiskFlag> = [
        .sipProtectedSystemPath, .protectedDirectory, .protectedFile,
        .secretOrCertificate, .projectManifest, .sourceOrConfig,
        .codingAgentMemoryOrConfig, .cloudSyncedLocalPath, .insideTrash
    ]

    public func shouldSkipTraversal(of url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents.map { $0.lowercased() }
        // Check protected directories FIRST — a path inside .ssh/node_modules must still be skipped.
        if components.contains(where: { protectedDirectoryNames.contains($0) }) {
            return true
        }
        let path = standardized.path.lowercased()
        if Self.sipProtectedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }),
           !Self.isAppleManagedTempSpace(path) {
            return true
        }
        // The Trash is never traversed — items already trashed are not cleanup candidates.
        if isInsideTrash(standardized) {
            return true
        }
        // node_modules is NOT skipped (we want to crawl into it to find cleanable artifacts)
        return false
    }

    /// Runs once per scanned item, so it uses plain string checks: an exact
    /// component appears as "/name/" in the slash-wrapped path, and a
    /// substring of one component never contains "/".
    public func cloudProvider(for url: URL) -> String? {
        let path = "/" + url.standardizedFileURL.path + "/"
        if path.contains("/Mobile Documents/") || path.contains("/iCloud Drive/") {
            return "iCloud"
        }
        let lowered = path.lowercased()
        if lowered.contains("google drive") || lowered.contains("/googledrive") {
            return "Google Drive"
        }
        if path.contains("/Dropbox/") {
            return "Dropbox"
        }
        if lowered.contains("onedrive") {
            return "OneDrive"
        }
        // File Provider folders (Box, pCloud, and others) live here.
        if lowered.contains("/library/cloudstorage/") {
            return "Cloud Storage"
        }
        return nil
    }

    private func isCodingAgentConfigPath(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let protectedAgentFolders: Set<String> = [".claude", ".codex", ".opencode", ".factory", ".openclaw", ".hermes", ".cursor", ".vscode"]
        guard components.contains(where: { protectedAgentFolders.contains($0) }) else {
            return false
        }
        let name = url.lastPathComponent.lowercased()
        return protectedAgentFolders.contains(name)
            || protectedFileNames.contains(name)
            || name == "memory"
            || name == "skills"
            || name == "commands"
            || name == "agents"
            || name == "plugins"
            || name == "mcp"
            || name == "auth.json"
            || name == "config.toml"
    }

    /// Central policy gate: the single decision point for whether `url` may be
    /// used as a cleanup target or action destination. Symlink ancestors are
    /// resolved here so literal paths cannot hide a protected location.
    /// `destination`, when provided, is validated with the same rules
    /// (move/archive/alias/symlink outputs).
    public func decide(target url: URL, isDirectory: Bool, destination: URL? = nil) -> PolicyDecision {
        let resolvedTarget = Self.resolved(url)
        let targetFlags = riskFlags(for: resolvedTarget, isDirectory: isDirectory)
        if !targetFlags.intersection(Self.allProtectionFlags).isEmpty {
            return .deny(reason: "Protected path: \(resolvedTarget.path)")
        }
        let folder = resolvedTarget.standardizedFileURL.path.lowercased() + "/"
        if Self.protectedFolders.contains(where: { $0.hasPrefix(folder) }) {
            return .deny(reason: "Contains protected data: \(resolvedTarget.path)")
        }
        guard let destination else {
            return .allow
        }
        let resolvedDestination = Self.resolved(destination)
        if isInsideTrash(resolvedDestination) {
            return .deny(reason: "Destination is inside the Trash: \(resolvedDestination.path)")
        }
        let destinationFlags = riskFlags(for: resolvedDestination, isDirectory: true)
        if !destinationFlags.intersection(Self.allProtectionFlags).isEmpty {
            return .deny(reason: "Destination is a protected path: \(resolvedDestination.path)")
        }
        return .allow
    }

    /// Never-delete folders in the home folder. Trashing a folder that holds
    /// one (~/Library/Developer/Xcode) would take it along.
    private static let protectedFolders: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path
        return [
            "Library/Keychains", "Library/Developer/Xcode/UserData", "Library/Developer/Xcode/Archives",
            "Library/Developer/CoreSimulator/Devices", "Library/Mail", "Library/MobileSync", ".ssh", ".gnupg"
        ].map { (home + "/" + $0).lowercased() }
    }()

    /// Resolve existing ancestors through symlinks so a path like
    /// ~/mylink → ~/Library/Keychains cannot masquerade as safe. Only the
    /// parent is resolved: the leaf itself may not exist yet (e.g. a move
    /// destination), and resolving a dangling leaf is a no-op anyway.
    static func resolved(_ url: URL) -> URL {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(url.lastPathComponent)
    }
}
