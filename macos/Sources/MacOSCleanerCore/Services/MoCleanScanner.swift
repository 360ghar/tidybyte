import Foundation
import os

/// Scans well-known macOS locations for cleanup opportunities, mirroring the
/// section-based approach of the open-source `mo clean` tool. Each
/// `SystemCleanSection` maps to a set of known paths and a `FindingCategory`.
///
/// Unlike `CleanerRuleEngine` (which classifies crawled user folders), this
/// scanner enumerates fixed system/user locations directly — fast and precise,
/// at the cost of requiring Full Disk Access for some protected system paths.
public actor MoCleanScanner {
    /// Registry of the 17 mo clean sections. Raw values match the corresponding
    /// `ScanMode` cases so `ScanMode.systemCleanSection` can bridge between them.
    public enum SystemCleanSection: String, CaseIterable, Codable, Sendable {
        case deepSystem
        case userEssentials
        case finderMetadata
        case macOSSystemCaches
        case sandboxedAppCaches
        case browsers
        case cloudStorage
        case officeApps
        case developerTools
        case devApplications
        case vmTools
        case applicationSupport
        case uninstalledAppData
        case appleSiliconUpdates
        case iosBackups
        case timeMachineBackups
        case largeFiles

        public var findingCategory: FindingCategory {
            switch self {
            case .deepSystem: .systemDeep
            case .userEssentials: .userEssentials
            case .finderMetadata: .finderMetadata
            case .macOSSystemCaches: .macOSSystemCache
            case .sandboxedAppCaches: .sandboxedAppCache
            case .browsers: .browserCache
            case .cloudStorage: .cloudStorageCache
            case .officeApps: .officeAppCache
            case .developerTools: .developerToolCache
            case .devApplications: .developmentAppCache
            case .vmTools: .vmToolCache
            case .applicationSupport: .applicationSupportCache
            case .uninstalledAppData: .uninstalledAppData
            case .appleSiliconUpdates: .appleSiliconUpdate
            case .iosBackups: .iosDeviceBackup
            case .timeMachineBackups: .timeMachineBackup
            case .largeFiles: .largeFileReview
            }
        }

        /// Default risk for findings in this section. Individual findings may override.
        public var risk: RiskLevel {
            switch self {
            case .deepSystem, .userEssentials, .finderMetadata, .macOSSystemCaches,
                 .sandboxedAppCaches, .officeApps, .applicationSupport:
                .low
            case .browsers, .developerTools, .devApplications, .vmTools, .uninstalledAppData:
                .medium
            case .cloudStorage, .appleSiliconUpdates:
                .medium
            case .iosBackups, .timeMachineBackups, .largeFiles:
                .high
            }
        }

        /// Whether findings in this section are review-only (not auto-deletable).
        /// High-risk, cloud-synced, broad-container sections (Application
        /// Support, sandboxed Containers), and deep-system paths (which mix
        /// caches with critical system logs under /private/var/log and
        /// /var/db/diagnostics) surface as `.inspectOnly` so the
        /// `SafetyAuditor` does not block them and the user reviews manually —
        /// trashing these wholesale could destroy app data or system diagnostics.
        public var isInspectOnly: Bool {
            switch self {
            case .deepSystem, .cloudStorage, .appleSiliconUpdates, .iosBackups,
                 .timeMachineBackups, .largeFiles, .applicationSupport,
                 .sandboxedAppCaches:
                true
            default:
                false
            }
        }

        public var confidence: Double { 0.86 }

        /// Well-known macOS locations to enumerate for this section.
        public func knownPaths(home: URL) -> [URL] {
            let lib = home.appendingPathComponent("Library", isDirectory: true)
            switch self {
            case .deepSystem:
                return [
                    URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
                    URL(fileURLWithPath: "/Library/Logs", isDirectory: true),
                    URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true),
                    URL(fileURLWithPath: "/private/var/log", isDirectory: true),
                    URL(fileURLWithPath: "/private/var/tmp", isDirectory: true),
                    URL(fileURLWithPath: "/var/db/diagnostics", isDirectory: true)
                ]
            case .userEssentials:
                return [
                    lib.appendingPathComponent("Caches", isDirectory: true),
                    lib.appendingPathComponent("Logs", isDirectory: true)
                ]
            case .finderMetadata:
                return [
                    lib.appendingPathComponent("Caches/com.apple.finder", isDirectory: true)
                ]
            case .macOSSystemCaches:
                return [
                    URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
                    URL(fileURLWithPath: "/System/Library/Caches", isDirectory: true)
                ]
            case .sandboxedAppCaches:
                return [
                    lib.appendingPathComponent("Containers", isDirectory: true),
                    lib.appendingPathComponent("Group Containers", isDirectory: true)
                ]
            case .browsers:
                let caches = lib.appendingPathComponent("Caches", isDirectory: true)
                return [
                    caches.appendingPathComponent("Google/Chrome", isDirectory: true),
                    caches.appendingPathComponent("Google/Chrome/GPUCache", isDirectory: true),
                    caches.appendingPathComponent("Puppeteer", isDirectory: true),
                    caches.appendingPathComponent("Microsoft Edge", isDirectory: true),
                    caches.appendingPathComponent("com.microsoft.edgemac", isDirectory: true),
                    caches.appendingPathComponent("BraveSoftware", isDirectory: true),
                    caches.appendingPathComponent("Firefox", isDirectory: true),
                    caches.appendingPathComponent("com.operasoftware.Opera", isDirectory: true)
                ]
            case .cloudStorage:
                let caches = lib.appendingPathComponent("Caches", isDirectory: true)
                return [
                    caches.appendingPathComponent("com.apple.bird", isDirectory: true),
                    caches.appendingPathComponent("Google Drive", isDirectory: true),
                    caches.appendingPathComponent("Dropbox", isDirectory: true)
                ]
            case .officeApps:
                let caches = lib.appendingPathComponent("Caches", isDirectory: true)
                return [
                    caches.appendingPathComponent("com.microsoft.Office", isDirectory: true),
                    caches.appendingPathComponent("Microsoft/Office", isDirectory: true)
                ]
            case .developerTools:
                let caches = lib.appendingPathComponent("Caches", isDirectory: true)
                return [
                    home.appendingPathComponent(".npm", isDirectory: true),
                    home.appendingPathComponent(".cache/pip", isDirectory: true),
                    home.appendingPathComponent(".cache/pnpm", isDirectory: true),
                    home.appendingPathComponent(".cache/uv", isDirectory: true),
                    home.appendingPathComponent(".cache/pre-commit", isDirectory: true),
                    home.appendingPathComponent(".bun", isDirectory: true),
                    home.appendingPathComponent(".local/share/pnpm", isDirectory: true),
                    home.appendingPathComponent(".dart_tool", isDirectory: true),
                    home.appendingPathComponent(".bundle", isDirectory: true),
                    lib.appendingPathComponent("Developer/CoreSimulator/Caches", isDirectory: true),
                    lib.appendingPathComponent("Caches/Homebrew", isDirectory: true),
                    caches.appendingPathComponent("com.anthropic.antigravity", isDirectory: true),
                    caches.appendingPathComponent("com.microsoft.vscode", isDirectory: true),
                    caches.appendingPathComponent("VSCode", isDirectory: true)
                ]
            case .devApplications:
                let caches = lib.appendingPathComponent("Caches", isDirectory: true)
                return [
                    lib.appendingPathComponent("Developer/Xcode/DerivedData", isDirectory: true),
                    lib.appendingPathComponent("Developer/Xcode/Archives", isDirectory: true),
                    caches.appendingPathComponent("com.microsoft.VSCode", isDirectory: true),
                    caches.appendingPathComponent("com.sublimetext", isDirectory: true),
                    caches.appendingPathComponent("com.openai.chat", isDirectory: true),
                    caches.appendingPathComponent("com.anthropic.claude", isDirectory: true),
                    caches.appendingPathComponent("com.spotify.client", isDirectory: true),
                    caches.appendingPathComponent("com.notion", isDirectory: true),
                    lib.appendingPathComponent("Logs/VSCode", isDirectory: true)
                ]
            case .vmTools:
                let caches = lib.appendingPathComponent("Caches", isDirectory: true)
                return [
                    caches.appendingPathComponent("com.docker.docker", isDirectory: true),
                    caches.appendingPathComponent("com.parallels", isDirectory: true),
                    caches.appendingPathComponent("com.vmware", isDirectory: true),
                    lib.appendingPathComponent("Containers/com.docker.docker", isDirectory: true)
                ]
            case .applicationSupport:
                return [
                    lib.appendingPathComponent("Application Support", isDirectory: true)
                ]
            case .uninstalledAppData:
                return [
                    "Application Support", "Caches", "HTTPStorages", "Preferences", "Saved Application State",
                    "WebKit", "Containers", "Logs", "Cookies", "LaunchAgents"
                ].map { lib.appendingPathComponent($0, isDirectory: true) }
            case .appleSiliconUpdates:
                return [
                    URL(fileURLWithPath: "/Library/Updates", isDirectory: true)
                ]
            case .iosBackups:
                return [
                    lib.appendingPathComponent("Application Support/MobileSync/Backup", isDirectory: true)
                ]
            case .timeMachineBackups:
                return [
                    URL(fileURLWithPath: "/Volumes", isDirectory: true)
                ]
            case .largeFiles:
                // Common large-file locations; individual files >= 1GB are surfaced.
                return [
                    home.appendingPathComponent("Downloads", isDirectory: true),
                    home.appendingPathComponent("Documents", isDirectory: true),
                    home.appendingPathComponent("Movies", isDirectory: true),
                    home.appendingPathComponent("Library/Application Support", isDirectory: true)
                ]
            }
        }

        public var summaryPrefix: String {
            switch self {
            case .deepSystem: "Deep system"
            case .userEssentials: "User essentials"
            case .finderMetadata: "Finder metadata"
            case .macOSSystemCaches: "macOS system caches"
            case .sandboxedAppCaches: "Sandboxed app caches"
            case .browsers: "Browsers"
            case .cloudStorage: "Cloud storage"
            case .officeApps: "Office applications"
            case .developerTools: "Developer tools"
            case .devApplications: "Development applications"
            case .vmTools: "Virtual machine tools"
            case .applicationSupport: "Application Support"
            case .uninstalledAppData: "Uninstalled app data"
            case .appleSiliconUpdates: "Apple Silicon updates"
            case .iosBackups: "iOS device backups"
            case .timeMachineBackups: "Time Machine backups"
            case .largeFiles: "Large files to review"
            }
        }
    }

    public struct ScanResult: Sendable {
        public let files: [FileRecord]
        public let findings: [Finding]
        public let recommendations: [Recommendation]
        /// Crawl errors (unreadable paths) encountered while scanning known
        /// paths, so sessions report permission gaps instead of hiding them.
        public var crawlErrors: Int

        public init(files: [FileRecord], findings: [Finding], recommendations: [Recommendation], crawlErrors: Int = 0) {
            self.files = files
            self.findings = findings
            self.recommendations = recommendations
            self.crawlErrors = crawlErrors
        }
    }

    private let crawler: FileCrawler
    private let policy: PathSafetyPolicy
    private let fileManager: FileManager
    /// Override for the user home directory. Tests point this at a temp directory
    /// so known paths resolve under a controlled fixture. `nil` uses the real home.
    private let homeDirectoryOverride: URL?
    /// Supplies the installed-app inventory for orphan checks. Tests inject a
    /// fixed index; nil asks Spotlight.
    private let installedApps: (@Sendable () async -> InstalledAppIndex?)?
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "MoCleanScanner")

    public init(
        crawler: FileCrawler = FileCrawler(),
        policy: PathSafetyPolicy = PathSafetyPolicy(),
        fileManager: FileManager = .default,
        homeDirectoryOverride: URL? = nil,
        installedApps: (@Sendable () async -> InstalledAppIndex?)? = nil
    ) {
        self.crawler = crawler
        self.policy = policy
        self.fileManager = fileManager
        self.homeDirectoryOverride = homeDirectoryOverride
        self.installedApps = installedApps
    }

    private func isAllowed(_ record: FileRecord) -> Bool {
        if case .allow = policy.decide(target: record.url, isDirectory: record.kind == .directory) {
            return true
        }
        return false
    }

    public func scan(section: SystemCleanSection, sessionID: String) async -> ScanResult {
        let home = homeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
        let candidateRoots = section.knownPaths(home: home)
        let closed = FullDiskAccess.closedAppDataFolders(home: home)
        // De-dupe nested roots: if one root is contained inside another, scanning
        // both double-counts bytes (Chrome root + Chrome/GPUCache were both listed).
        let roots = Self.deduplicatedRoots(candidateRoots.filter {
            fileManager.fileExists(atPath: $0.path) && !closed.contains($0.standardizedFileURL.path)
        })

        guard !roots.isEmpty else {
            logger.info("\(section.summaryPrefix, privacy: .public): no known paths present.")
            return ScanResult(files: [], findings: [], recommendations: [])
        }

        // Special-case sections that need bespoke classification.
        switch section {
        case .uninstalledAppData:
            return await scanUninstalledAppData(roots: roots, section: section, sessionID: sessionID)
        case .largeFiles:
            return await scanLargeFiles(roots: roots, section: section, sessionID: sessionID)
        case .timeMachineBackups:
            return await scanTimeMachine(section: section, sessionID: sessionID)
        case .devApplications:
            let caches = await scanCacheDirectories(roots: roots, section: section, sessionID: sessionID)
            let support = await scanDeviceSupport(home: home, section: section, sessionID: sessionID)
            return ScanResult(
                files: caches.files + support.files, findings: caches.findings + support.findings,
                recommendations: caches.recommendations + support.recommendations,
                crawlErrors: caches.crawlErrors + support.crawlErrors)
        default:
            return await scanCacheDirectories(roots: roots, section: section, sessionID: sessionID)
        }
    }

    // MARK: - Cache-style sections

    /// Risk for a cache entry living under `rootPath`. Whole-system cache roots
    /// (e.g. /Library/Caches, /System/Library/Caches — anything outside the
    /// user's home) may be shared by the OS or other users, so entries under
    /// them are at least medium risk. Individual user-level cache entries stay
    /// low risk.
    static func cacheEntryRisk(underRoot rootPath: String, home: URL) -> RiskLevel {
        let homePath = home.standardizedFileURL.path
        let isWholeSystem = !(rootPath == homePath || rootPath.hasPrefix(homePath + "/"))
        return isWholeSystem ? .medium : .low
    }

    /// True when the directory is a caches CONTAINER (e.g. ~/Library/Caches,
    /// /Library/Caches, /System/Library/Caches). Such roots must never be
    /// proposed for cleanup themselves; only their individual entries may be.
    private func isCachesContainer(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased() == "caches"
    }

    /// Drops any root fully contained inside another root, keeping the outermost.
    /// Nested entries (e.g. Chrome + Chrome/GPUCache) must never be scanned twice:
    /// their bytes would be double-counted across overlapping findings.
    static func deduplicatedRoots(_ roots: [URL]) -> [URL] {
        let paths = roots.map { $0.standardizedFileURL.path }
        return roots.enumerated().compactMap { index, root in
            let path = paths[index]
            let isContainedInOther = paths.enumerated().contains { otherIndex, otherPath in
                otherIndex != index && path.hasPrefix(otherPath + "/")
            }
            return isContainedInOther ? nil : root
        }
    }

    /// Direct children of a scanned root (one level deep), used to surface
    /// individual cache entries instead of the container root itself.
    private func directChildren(of rootPath: String, in files: [FileRecord]) -> [FileRecord] {
        files.filter { record in
            (record.displayPath as NSString).deletingLastPathComponent == rootPath
        }
    }

    /// Reclaimable-byte index for a crawl: path → total bytes of everything
    /// under that path (own size for files, full subtree for directories).
    ///
    /// Built with one sorted reverse pass — children finalize before parents,
    /// and each path folds its finished total into its direct parent. Replaces
    /// the previous O(children × files) `hasPrefix` scans per queried directory.
    static func buildSubtreeByteIndex(files: [FileRecord]) -> [String: Int64] {
        let entries = files.map { ($0.displayPath, max(0, $0.sizeBytes)) }
            .sorted { $0.0 < $1.0 }
        var subtreeBytes: [String: Int64] = [:]
        for (path, size) in entries.reversed() {
            let total = size + (subtreeBytes[path] ?? 0)
            subtreeBytes[path] = total
            if let slash = path.lastIndex(of: "/") {
                subtreeBytes[String(path[..<slash]), default: 0] += total
            }
        }
        return subtreeBytes
    }

    /// Generic cache-directory scan: crawl each root, group by root, sum subtree
    /// sizes, emit one finding per non-empty root directory.
    private func scanCacheDirectories(
        roots: [URL],
        section: SystemCleanSection,
        sessionID: String
    ) async -> ScanResult {
        let home = homeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
        let (files, crawlErrors) = await crawler.crawl(rootURLs: roots, sessionID: sessionID)
        let subtreeIndex = Self.buildSubtreeByteIndex(files: files)

        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        var relevantFiles: [FileRecord] = []

        for root in roots {
            let rootPath = root.standardizedFileURL.path

            // Never propose a caches ROOT directory itself: trashing the entire
            // ~/Library/Caches or /Library/Caches container is far broader than
            // the rebuildable caches inside it. Surface only its direct entries.
            if isCachesContainer(root) {
                for child in directChildren(of: rootPath, in: files) {
                    guard isAllowed(child) else { continue }
                    let bytes = subtreeIndex[child.displayPath] ?? max(0, child.sizeBytes)
                    guard bytes > 0 else { continue }
                    let risk = Self.cacheEntryRisk(underRoot: rootPath, home: home)
                    var childRecord = child
                    if childRecord.kind == .directory || childRecord.kind == .package {
                        // Directories report 0 size from the crawler; carry the
                        // reclaimable subtree total so the planner sizes the
                        // action correctly.
                        childRecord.sizeBytes = bytes
                    }
                    let findingID = UUID().uuidString
                    let actionType: ActionType = section.isInspectOnly ? .inspectOnly : .moveToTrash
                    findings.append(Finding(
                        id: findingID,
                        scanSessionID: sessionID,
                        category: section.findingCategory,
                        severity: risk,
                        confidence: section.confidence,
                        bytesReclaimable: bytes,
                        summary: String(localized: "\(section.summaryPrefix): \(child.fileName) (\(bytes.formattedByteCount))", comment: "Mo clean cache entry finding summary"),
                        evidence: ["path": childRecord.displayPath, "bytes": String(bytes), "root": rootPath],
                        targetFileIDs: [childRecord.id]
                    ))
                    recommendations.append(recommendation(
                        findingID: findingID,
                        targetFileIDs: [childRecord.id],
                        section: section,
                        risk: risk,
                        actionType: actionType,
                        bytes: bytes,
                        reason: cacheEntryReason(risk: risk, path: childRecord.displayPath, rootPath: rootPath)
                    ))
                    relevantFiles.append(childRecord)
                }
                continue
            }

            guard var rootRecord = files.first(where: { $0.displayPath == rootPath }) else { continue }
            guard isAllowed(rootRecord) else { continue }

            let subtreeBytes = subtreeIndex[rootPath] ?? 0
            guard subtreeBytes > 0 else { continue }

            // Directories report 0 size from the crawler; carry the reclaimable
            // subtree total on the record so the planner and dashboard size it
            // correctly (the planner sums target `sizeBytes`).
            rootRecord.sizeBytes = subtreeBytes
            let findingID = UUID().uuidString
            let actionType: ActionType = section.isInspectOnly ? .inspectOnly : .moveToTrash
            let risk = section.risk
            let finding = Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: section.findingCategory,
                severity: risk,
                confidence: section.confidence,
                bytesReclaimable: subtreeBytes,
                summary: String(localized: "\(section.summaryPrefix): \(root.lastPathComponent) (\(subtreeBytes.formattedByteCount))", comment: "Mo clean section finding summary"),
                evidence: ["path": rootPath, "bytes": String(subtreeBytes)],
                targetFileIDs: [rootRecord.id]
            )
            findings.append(finding)
            recommendations.append(recommendation(
                findingID: findingID,
                targetFileIDs: [rootRecord.id],
                section: section,
                risk: risk,
                actionType: actionType,
                bytes: subtreeBytes,
                reason: reason(for: section, rootPath: rootPath)
            ))
            relevantFiles.append(rootRecord)
        }

        // Surface the records that back each finding so the Why Panel and
        // executor can resolve targets. Contents of proposed directories are not
        // enumerated individually — trashing the directory handles the subtree.
        return ScanResult(files: relevantFiles, findings: findings, recommendations: recommendations, crawlErrors: crawlErrors)
    }

    // MARK: - Uninstalled app data

    /// Data named after an app that is no longer installed. An entry counts
    /// only when the full app inventory is known, no installed app owns the
    /// bundle ID (helpers included), and nothing in it changed for 30 days.
    /// Launch agents whose program no longer exists are orphans too.
    private func scanUninstalledAppData(
        roots: [URL],
        section: SystemCleanSection,
        sessionID: String
    ) async -> ScanResult {
        let home = homeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
        let inventory: InstalledAppIndex?
        if let installedApps { inventory = await installedApps() } else { inventory = await InstalledAppIndex.live(home: home) }
        guard let inventory else {
            logger.info("Spotlight inventory unavailable; orphan detection skipped.")
            return ScanResult(files: [], findings: [], recommendations: [])
        }
        var orphanIDs: [URL: String] = [:]
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        for root in roots {
            for entry in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                guard let bundleID = orphanBundleID(for: entry, inLaunchAgents: root.lastPathComponent == "LaunchAgents"),
                    !inventory.isInstalled(bundleID), Self.modified(entry) < cutoff else { continue }
                orphanIDs[entry.standardizedFileURL] = bundleID
            }
        }
        guard !orphanIDs.isEmpty else { return ScanResult(files: [], findings: [], recommendations: []) }
        let (files, crawlErrors) = await crawler.crawl(rootURLs: Array(orphanIDs.keys), sessionID: sessionID)
        let subtreeIndex = Self.buildSubtreeByteIndex(files: files)
        let recentEntries = Self.entriesChanged(after: cutoff, in: files, entries: Set(orphanIDs.keys.map(\.path)))
        var recordsByID: [String: [FileRecord]] = [:]
        for var record in files {
            guard let bundleID = orphanIDs[record.url.standardizedFileURL], !recentEntries.contains(record.displayPath),
                isAllowed(record) else { continue }
            if record.kind == .directory { record.sizeBytes = subtreeIndex[record.displayPath] ?? 0 }
            recordsByID[bundleID, default: []].append(record)
        }
        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        for (bundleID, records) in recordsByID.sorted(by: { $0.key < $1.key }) {
            let bytes = records.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let findingID = UUID().uuidString
            findings.append(Finding(
                id: findingID, scanSessionID: sessionID, category: section.findingCategory, severity: .medium,
                confidence: 0.7, bytesReclaimable: bytes,
                summary: String(
                    localized: "Leftovers of a removed app: \(bundleID) (\(records.count) items, \(bytes.formattedByteCount))",
                    comment: "Uninstalled app data finding"),
                evidence: ["bundle_id": bundleID, "orphan_bundle_id": bundleID, "bytes": String(bytes)],
                targetFileIDs: records.map(\.id)))
            recommendations.append(recommendation(
                findingID: findingID, targetFileIDs: records.map(\.id), section: section, risk: .medium,
                actionType: .moveToTrash, bytes: bytes,
                reason: String(
                    localized: "No installed app uses \(bundleID), and none of its data changed in 30 days.",
                    comment: "Uninstalled app data recommendation")))
        }
        return ScanResult(
            files: recordsByID.values.flatMap { $0 }, findings: findings, recommendations: recommendations,
            crawlErrors: crawlErrors)
    }

    /// Bundle ID an entry is named after, or for a launch agent the label of
    /// a job whose program is gone. Nil when the entry is not an orphan candidate.
    private func orphanBundleID(for entry: URL, inLaunchAgents: Bool) -> String? {
        if inLaunchAgents {
            guard entry.pathExtension == "plist",
                let job = NSDictionary(contentsOf: entry) as? [String: Any],
                let label = job["Label"] as? String, InstalledAppIndex.isThirdPartyBundleID(label),
                let program = (job["Program"] as? String) ?? (job["ProgramArguments"] as? [String])?.first,
                program.hasPrefix("/"), !fileManager.fileExists(atPath: program) else { return nil }
            return label
        }
        var name = entry.lastPathComponent
        for suffix in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return InstalledAppIndex.isThirdPartyBundleID(name) ? name : nil
    }

    /// Entries with anything inside changed after `cutoff`: still in use.
    private static func entriesChanged(after cutoff: Date, in files: [FileRecord], entries: Set<String>) -> Set<String> {
        var changed = Set<String>()
        for record in files where (record.modifiedAt ?? .distantFuture) >= cutoff {
            var path = record.displayPath
            while path.count > 1, !entries.contains(path) { path = (path as NSString).deletingLastPathComponent }
            changed.insert(path)
        }
        return changed
    }

    /// Unknown dates count as recent, so they never make an orphan.
    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
    }

    // MARK: - Large files

    private func scanLargeFiles(
        roots: [URL],
        section: SystemCleanSection,
        sessionID: String
    ) async -> ScanResult {
        let (files, crawlErrors) = await crawler.crawl(rootURLs: roots, sessionID: sessionID)
        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        var relevantFiles: [FileRecord] = []
        let threshold: Int64 = 1_000_000_000
        for record in files where record.kind == .regularFile && record.sizeBytes >= threshold {
            guard isAllowed(record) else { continue }
            let findingID = UUID().uuidString
            findings.append(Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: section.findingCategory,
                severity: .high,
                confidence: 0.7,
                bytesReclaimable: record.sizeBytes,
                summary: String(localized: "Large file: \(record.fileName) (\(record.sizeBytes.formattedByteCount))", comment: "Large file review finding"),
                evidence: ["path": record.displayPath, "bytes": String(record.sizeBytes)],
                targetFileIDs: [record.id]
            ))
            recommendations.append(recommendation(
                findingID: findingID,
                targetFileIDs: [record.id],
                section: section,
                risk: .high,
                actionType: .inspectOnly,
                bytes: record.sizeBytes,
                reason: String(localized: "This file is over 1 GB. Review whether it can be moved or deleted.", comment: "Large file review recommendation")
            ))
            relevantFiles.append(record)
        }
        return ScanResult(files: relevantFiles, findings: findings, recommendations: recommendations, crawlErrors: crawlErrors)
    }

    // MARK: - Time Machine

    /// Local Time Machine snapshots on the startup disk. macOS thins them
    /// itself when space runs low, so they are review-only here.
    private func scanTimeMachine(
        section: SystemCleanSection,
        sessionID: String
    ) async -> ScanResult {
        let listing = await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/tmutil"), arguments: ["listlocalsnapshotdates", "/"], timeout: 10)
        let dates = Self.localSnapshotDates(listing.stdout)
        guard listing.exitCode == 0, let oldest = dates.first else {
            return ScanResult(files: [], findings: [], recommendations: [])
        }
        let findingID = UUID().uuidString
        let finding = Finding(
            id: findingID, scanSessionID: sessionID, category: section.findingCategory, severity: .high,
            confidence: 0.9, bytesReclaimable: 0,
            summary: String(
                localized: "\(dates.count) local Time Machine snapshots, oldest \(oldest)",
                comment: "Time Machine local snapshot finding"),
            evidence: ["snapshots": dates.joined(separator: ", ")],
            targetFileIDs: [])
        let rec = recommendation(
            findingID: findingID, targetFileIDs: [], section: section, risk: .high, actionType: .inspectOnly, bytes: 0,
            reason: String(
                localized: """
                    macOS removes local snapshots when it needs the space. To remove them now, run \
                    "tmutil thinlocalsnapshots / 999999999999 4" in Terminal.
                    """,
                comment: "Time Machine recommendation"))
        return ScanResult(files: [], findings: [finding], recommendations: [rec])
    }

    /// Lines like `2026-10-28-101530` from `tmutil listlocalsnapshotdates`, oldest first.
    static func localSnapshotDates(_ output: String) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.wholeMatch(of: /\d{4}-\d{2}-\d{2}-\d{6}/) != nil }.sorted()
    }

    // MARK: - Xcode device support

    /// Older device-support folders per platform. Xcode needs only the newest
    /// for the devices you use and rebuilds others when a device connects.
    private func scanDeviceSupport(home: URL, section: SystemCleanSection, sessionID: String) async -> ScanResult {
        let xcode = home.appendingPathComponent("Library/Developer/Xcode", isDirectory: true)
        var older: [URL] = []
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            let folder = xcode.appendingPathComponent("\(platform) DeviceSupport", isDirectory: true)
            let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            older += Self.olderDeviceSupport(entries)
        }
        guard !older.isEmpty else { return ScanResult(files: [], findings: [], recommendations: []) }
        let (files, crawlErrors) = await crawler.crawl(rootURLs: older, sessionID: sessionID)
        let index = Self.buildSubtreeByteIndex(files: files)
        let roots = Set(older.map(\.standardizedFileURL))
        let records = files.filter { roots.contains($0.url.standardizedFileURL) && isAllowed($0) }.map { record in
            var sized = record
            sized.sizeBytes = index[record.displayPath] ?? record.sizeBytes
            return sized
        }
        guard !records.isEmpty else { return ScanResult(files: [], findings: [], recommendations: [], crawlErrors: crawlErrors) }
        let bytes = records.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let findingID = UUID().uuidString
        let finding = Finding(
            id: findingID, scanSessionID: sessionID, category: section.findingCategory, severity: .medium,
            confidence: 0.85, bytesReclaimable: bytes,
            summary: String(
                localized: "\(records.count) older Xcode device support folders (\(bytes.formattedByteCount))",
                comment: "Device support finding"),
            evidence: ["kept": "newest per platform"], targetFileIDs: records.map(\.id))
        let rec = recommendation(
            findingID: findingID, targetFileIDs: records.map(\.id), section: section, risk: .medium,
            actionType: .moveToTrash, bytes: bytes,
            reason: String(
                localized: "Keeps the newest version per platform. Xcode copies symbols again when a device with an older system connects.",
                comment: "Device support recommendation"))
        return ScanResult(files: records, findings: [finding], recommendations: [rec], crawlErrors: crawlErrors)
    }

    /// Every entry except the newest system version. Names look like
    /// `iPhone14,2 26.5 (23F77)` or `17.2 (21C52)`; unparsable names are kept.
    static func olderDeviceSupport(_ entries: [URL]) -> [URL] {
        let versioned = entries.compactMap { url -> (URL, [Int])? in
            guard let match = url.lastPathComponent.firstMatch(of: /(\d+(?:\.\d+)*) \(/) else { return nil }
            return (url, match.1.split(separator: ".").compactMap { Int($0) })
        }
        guard let newest = versioned.max(by: { $0.1.lexicographicallyPrecedes($1.1) }) else { return [] }
        return versioned.filter { $0.1 != newest.1 }.map(\.0)
    }

    // MARK: - Helpers

    private func recommendation(
        findingID: String,
        targetFileIDs: [String],
        section: SystemCleanSection,
        risk: RiskLevel,
        actionType: ActionType,
        bytes: Int64,
        reason: String
    ) -> Recommendation {
        Recommendation(
            id: UUID().uuidString,
            findingID: findingID,
            actionType: actionType,
            targetFileIDs: targetFileIDs,
            confidence: section.confidence,
            risk: risk,
            reason: reason,
            expectedBytesReclaimed: bytes,
            requiresConfirmation: true,
            llmTraceID: nil,
            policyTraceID: "moclean_\(section.rawValue)_rule"
        )
    }

    private func reason(for section: SystemCleanSection, rootPath: String) -> String {
        if section.isInspectOnly {
            return String(localized: "\(section.summaryPrefix) at \(rootPath) is high-risk or cloud-managed. Review manually before removing.", comment: "Mo clean inspect-only recommendation reason")
        }
        return String(localized: "\(section.summaryPrefix) cache/log at \(rootPath) is rebuildable. Review before moving to Trash.", comment: "Mo clean cache recommendation reason")
    }

    private func cacheEntryReason(risk: RiskLevel, path: String, rootPath: String) -> String {
        if risk == .medium {
            return String(localized: "Cache entry under the system-wide caches root at \(rootPath). This location may be shared by the OS or other apps, review carefully before removing.", comment: "Mo clean whole-system cache entry recommendation reason")
        }
        return String(localized: "Cache entry at \(path) is rebuildable. Review before moving to Trash.", comment: "Mo clean user cache entry recommendation reason")
    }
}
