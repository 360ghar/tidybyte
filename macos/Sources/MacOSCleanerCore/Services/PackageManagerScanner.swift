import Foundation
import os

public actor PackageManagerScanner {
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "PackageManagerScanner")
    private let commandTimeout: TimeInterval
    typealias Runner = @Sendable (URL, [String], TimeInterval) async -> ProcessResult
    private let run: Runner
    private let locate: @Sendable (String) -> URL?

    public init(commandTimeout: TimeInterval = 8) {
        self.init(commandTimeout: commandTimeout, runner: nil, locate: nil)
    }

    /// Tests inject a runner and a tool locator; nothing real is executed.
    init(commandTimeout: TimeInterval = 8, runner: Runner?, locate: (@Sendable (String) -> URL?)?) {
        self.commandTimeout = commandTimeout
        self.run = runner ?? { await ProcessRunner.run($0, arguments: $1, timeout: $2) }
        self.locate = locate ?? Self.defaultExecutable(named:)
    }

    public func scan(sessionID: String) async -> ([Finding], [Recommendation], [PackageCleanupCandidate]) {
        // Probe all package managers concurrently: each is a subprocess with an
        // 8 s timeout. The actor runs other probes while one waits on its tool.
        async let brew = homebrewCandidates()
        async let docker = dockerCandidates()
        async let npm = npmCandidates()
        async let pip = pipCandidates()
        async let pnpm = pnpmCandidates()
        async let simulators = simulatorCandidates()
        let candidates = await brew + docker + npm + pip + pnpm + simulators

        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        for candidate in candidates {
            let findingID = UUID().uuidString
            findings.append(Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: candidate.category,
                severity: candidate.risk,
                confidence: 0.82,
                bytesReclaimable: candidate.estimatedBytes ?? 0,
                summary: candidate.title,
                evidence: [
                    "command": ([candidate.commandPath.path] + candidate.arguments).joined(separator: " "),
                    "dry_run": candidate.dryRunOutput
                ],
                targetFileIDs: [candidate.id]
            ))
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .runPackageManagerCleanup,
                targetFileIDs: [candidate.id],
                confidence: 0.82,
                risk: candidate.risk,
                reason: String(localized: "Use the package manager's own cleanup command after reviewing its dry-run output. This is not fully undoable.", comment: "Package cleanup recommendation reason"),
                expectedBytesReclaimed: candidate.estimatedBytes ?? 0,
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "package_manager_dry_run"
            ))
        }
        return (findings, recommendations, candidates)
    }

    private func homebrewCandidates() async -> [PackageCleanupCandidate] {
        guard let brew = locate("brew") else {
            return []
        }
        let cleanup = await run(brew, ["cleanup", "--prune=all", "--dry-run"], commandTimeout)
        let autoremove = await run(brew, ["autoremove", "--dry-run"], commandTimeout)
        var output: [PackageCleanupCandidate] = []
        if cleanup.exitCode == 0, !cleanup.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output.append(PackageCleanupCandidate(
                id: "homebrew_cleanup",
                title: String(localized: "Homebrew cleanup dry-run has stale downloads or old versions to review.", comment: "Homebrew cleanup finding title"),
                commandPath: brew,
                arguments: ["cleanup", "--prune=all"],
                dryRunOutput: cleanup.stdout,
                risk: .medium,
                category: .packageManagerCleanup,
                estimatedBytes: Self.brewFreedBytes(cleanup.stdout)
            ))
        }
        if autoremove.exitCode == 0, !autoremove.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output.append(PackageCleanupCandidate(
                id: "homebrew_autoremove",
                title: String(localized: "Homebrew autoremove dry-run found unused dependencies.", comment: "Homebrew autoremove finding title"),
                commandPath: brew,
                arguments: ["autoremove"],
                dryRunOutput: autoremove.stdout,
                risk: .high,
                category: .packageManagerCleanup
            ))
        }
        return output
    }

    private func dockerCandidates() async -> [PackageCleanupCandidate] {
        guard let docker = locate("docker") else {
            return []
        }
        let result = await run(docker, ["system", "df"], commandTimeout)
        guard result.exitCode == 0, !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return [
            PackageCleanupCandidate(
                id: "docker_builder_prune",
                title: String(
                    localized: "Docker build cache can be cleared. Images and containers stay.",
                    comment: "Docker builder prune finding title"),
                commandPath: docker,
                arguments: ["builder", "prune", "--force"],
                dryRunOutput: result.stdout,
                risk: .low,
                category: .dockerCleanup
            ),
            PackageCleanupCandidate(
                id: "docker_safe_prune",
                title: String(localized: "Docker safe cleanup can prune stopped containers, dangling images, and build cache.", comment: "Docker safe cleanup finding title"),
                commandPath: docker,
                arguments: ["system", "prune", "--force"],
                dryRunOutput: result.stdout,
                risk: .medium,
                category: .dockerCleanup
            ),
            PackageCleanupCandidate(
                id: "docker_risky_prune",
                title: String(localized: "Docker aggressive cleanup prunes stopped containers, dangling images, build cache, AND unused volumes. Volumes may contain persistent data.", comment: "Docker aggressive cleanup finding title"),
                commandPath: docker,
                arguments: ["system", "prune", "--volumes", "--force"],
                dryRunOutput: result.stdout,
                risk: .high,
                category: .dockerCleanup
            ),
            PackageCleanupCandidate(
                id: "docker_volume_prune",
                title: String(localized: "Docker Volume Prune (risky. Removes named volumes)", comment: "Docker volume prune finding title"),
                commandPath: docker,
                arguments: ["volume", "prune", "--force"],
                dryRunOutput: result.stdout,
                risk: .high,
                category: .dockerCleanup
            )
        ]
    }

    private func npmCandidates() async -> [PackageCleanupCandidate] {
        guard let npm = locate("npm") else {
            return []
        }
        let cachePathResult = await run(npm, ["config", "get", "cache"], commandTimeout)
        guard cachePathResult.exitCode == 0 else {
            return []
        }
        let cachePath = cachePathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var output: [PackageCleanupCandidate] = []
        // npm cache ls: read-only listing of cache entries. (The previous
        // `npm cache verify` rewrote cache state and could take minutes during
        // what the user experiences as a metadata scan — removed.)
        let listResult = await run(npm, ["cache", "ls"], commandTimeout)
        let dryRunText = listResult.exitCode == 0 && !listResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? listResult.stdout
            : String(localized: "Cache directory: \(cachePath)", comment: "npm cache fallback dry-run output")
        output.append(PackageCleanupCandidate(
            id: "npm_cache_list",
            title: String(localized: "npm cache is visible at \(cachePath). Review before cleaning.", comment: "npm cache list finding title"),
            commandPath: npm,
            arguments: ["cache", "ls"],
            dryRunOutput: dryRunText,
            risk: .low,
            category: .packageManagerCleanup
        ))
        // npm cache clean --force: destructive, show cache path as evidence
        output.append(PackageCleanupCandidate(
            id: "npm_cache_clean",
            title: String(localized: "npm cache clean will delete the entire npm cache at \(cachePath). Packages will be re-downloaded on next install.", comment: "npm cache clean finding title"),
            commandPath: npm,
            arguments: ["cache", "clean", "--force"],
            dryRunOutput: String(localized: "Cache directory: \(cachePath)", comment: "npm cache clean evidence output"),
            risk: .medium,
            category: .packageManagerCleanup
        ))
        return output
    }

    private func pipCandidates() async -> [PackageCleanupCandidate] {
        guard let pip = locate("pip3") ?? locate("pip") else {
            return []
        }
        let dirResult = await run(pip, ["cache", "dir"], commandTimeout)
        guard dirResult.exitCode == 0 else {
            return []
        }
        let cacheDir = dirResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Run `pip cache list` to show the user what is actually cached.
        let listResult = await run(pip, ["cache", "list"], commandTimeout)
        let dryRunText = listResult.exitCode == 0 && !listResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? listResult.stdout
            : String(localized: "Cache directory: \(cacheDir)", comment: "pip cache fallback dry-run output")
        return [
            PackageCleanupCandidate(
                id: "pip_cache_dir",
                title: String(localized: "pip cache at \(cacheDir). Review cache contents before purging.", comment: "pip cache finding title"),
                commandPath: pip,
                arguments: ["cache", "list"],
                dryRunOutput: dryRunText,
                risk: .low,
                category: .packageManagerCleanup
            )
        ]
    }

    static func defaultExecutable(named name: String) -> URL? {
        // /usr/bin developer tools (pip3, xcrun) are shims: without the Command
        // Line Tools, running one opens the "install the tools" dialog.
        let folders = ["/opt/homebrew/bin", "/usr/local/bin"] + (hasDeveloperTools ? ["/usr/bin"] : []) + ["/bin"]
        return folders.map { URL(fileURLWithPath: "\($0)/\(name)") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// `xcode-select -p` prints an existing developer folder. It never opens the install dialog.
    static let hasDeveloperTools: Bool = {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let path = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        return process.terminationStatus == 0 && !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }()

    private func pnpmCandidates() async -> [PackageCleanupCandidate] {
        guard let pnpm = locate("pnpm") else { return [] }
        let store = await run(pnpm, ["store", "path"], commandTimeout)
        let path = store.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.exitCode == 0, !path.isEmpty else { return [] }
        return [PackageCleanupCandidate(
            id: "pnpm_store_prune",
            title: String(
                localized: "pnpm store at \(path) can drop packages no project uses.",
                comment: "pnpm store prune finding title"),
            commandPath: pnpm, arguments: ["store", "prune"],
            dryRunOutput: String(localized: "Store: \(path)", comment: "pnpm store evidence"),
            risk: .low, category: .packageManagerCleanup)]
    }

    /// Simulators whose runtime is gone. `simctl delete unavailable` removes
    /// only those, through Xcode's own tool.
    private func simulatorCandidates() async -> [PackageCleanupCandidate] {
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        guard locate("xcrun") != nil else { return [] }
        let listing = await run(xcrun, ["simctl", "list", "devices", "unavailable", "-j"], commandTimeout)
        guard listing.exitCode == 0 else { return [] }
        let count = Self.unavailableSimulatorCount(listing.stdout)
        guard count > 0 else { return [] }
        return [PackageCleanupCandidate(
            id: "simctl_delete_unavailable",
            title: String(
                localized: "\(count) simulators belong to runtimes that are no longer installed.",
                comment: "Unavailable simulators finding title"),
            commandPath: xcrun, arguments: ["simctl", "delete", "unavailable"],
            dryRunOutput: listing.stdout, risk: .medium, category: .developerToolCache,
            blockingProcesses: ["Simulator", "Xcode"])]
    }

    /// "This operation would free approximately 1.2GB of disk space."
    /// Homebrew's `disk_usage_readable` uses powers of 1024.
    static func brewFreedBytes(_ output: String) -> Int64? {
        guard let match = output.firstMatch(of: /free approximately ([0-9.]+)\s*([KMGT]?B)/) else { return nil }
        let units: [Substring: Double] = ["B": 1, "KB": 0x400, "MB": 0x100000, "GB": 0x40000000, "TB": 0x10000000000]
        guard let value = Double(match.1), let unit = units[match.2] else { return nil }
        return Int64(value * unit)
    }

    static func unavailableSimulatorCount(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = root["devices"] as? [String: [Any]] else { return 0 }
        return devices.values.reduce(0) { $0 + $1.count }
    }

}
