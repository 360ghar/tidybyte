import Foundation
import os
import Security

/// A single installed macOS application discovered under /Applications or
/// ~/Applications. Value type so the UI can hold it across actor hops.
public struct InstalledApplication: Sendable, Identifiable, Equatable {
    /// Bundle identifier when the app exposes one, otherwise `"path:<path>"`.
    public var id: String
    public var name: String
    public var bundleURL: URL
    public var bundleIdentifier: String?
    public var bundleSizeBytes: Int64

    public init(id: String, name: String, bundleURL: URL, bundleIdentifier: String?, bundleSizeBytes: Int64) {
        self.id = id
        self.name = name
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.bundleSizeBytes = bundleSizeBytes
    }
}

/// Where a footprint item lives. System locations are shared with the OS or
/// other users, so uninstall recommendations covering them carry an explicit
/// review warning even though the audit math matches user-level items.
public enum FootprintLocation: String, Sendable, CaseIterable {
    case bundle
    case caches
    case preferences
    case applicationSupport
    case logs
    case httpStorages
    case containers
    case groupContainers
    case savedState
    case webKit
    case cookies
    case applicationScripts
    case launchAgents
    case systemCaches
    case systemApplicationSupport
    case systemPreferences
    case systemLogs
    case systemLaunchAgents
    case systemLaunchDaemons
    case privilegedHelperTools

    public var displayName: String {
        switch self {
        case .bundle: String(localized: "App Bundle", comment: "Footprint location: app bundle")
        case .caches: String(localized: "Caches", comment: "Footprint location: caches")
        case .preferences: String(localized: "Preferences", comment: "Footprint location: preferences")
        case .applicationSupport: String(localized: "Application Support", comment: "Footprint location: application support")
        case .logs: String(localized: "Logs", comment: "Footprint location: logs")
        case .httpStorages: String(localized: "HTTP Storage", comment: "Footprint location: HTTP storage")
        case .containers: String(localized: "Containers", comment: "Footprint location: containers")
        case .groupContainers: String(localized: "Group Containers", comment: "Footprint location: group containers")
        case .savedState: String(localized: "Saved State", comment: "Footprint location: saved state")
        case .webKit: String(localized: "WebKit Data", comment: "Footprint location: WebKit")
        case .cookies: String(localized: "Cookies", comment: "Footprint location: cookies")
        case .applicationScripts: String(localized: "Application Scripts", comment: "Footprint location: scripts")
        case .launchAgents: String(localized: "Launch Agents", comment: "Footprint location: user launch agents")
        case .systemLaunchAgents:
            String(localized: "System Launch Agents", comment: "Footprint location: /Library/LaunchAgents")
        case .systemLaunchDaemons:
            String(localized: "System Launch Daemons", comment: "Footprint location: /Library/LaunchDaemons")
        case .privilegedHelperTools:
            String(localized: "Privileged Helpers", comment: "Footprint location: /Library/PrivilegedHelperTools")
        case .systemCaches: String(localized: "System Caches", comment: "Footprint location: system caches")
        case .systemApplicationSupport: String(localized: "System Application Support", comment: "Footprint location: system application support")
        case .systemPreferences: String(localized: "System Preferences", comment: "Footprint location: system preferences")
        case .systemLogs: String(localized: "System Logs", comment: "Footprint location: system logs")
        }
    }

    /// True for locations outside the user's home — potentially shared.
    public var isSystemWide: Bool {
        switch self {
        case .systemCaches, .systemApplicationSupport, .systemPreferences, .systemLogs,
            .systemLaunchAgents, .systemLaunchDaemons, .privilegedHelperTools:
            true
        default:
            false
        }
    }
}

/// How sure the match is. Only `certain` and `likely` items are staged for
/// Trash; `possible` items stay review-only.
public enum FootprintConfidence: Int, Sendable, Comparable, CaseIterable {
    case possible, likely, certain

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .possible: String(localized: "Possible match", comment: "Footprint confidence")
        case .likely: String(localized: "Likely match", comment: "Footprint confidence")
        case .certain: String(localized: "Certain match", comment: "Footprint confidence")
        }
    }
}

/// One file or directory belonging to an application's footprint, with the
/// evidence that tied it to the app.
public struct ApplicationFootprintItem: Sendable, Identifiable, Equatable {
    public var id: String { url.path }
    public var url: URL
    public var location: FootprintLocation
    public var sizeBytes: Int64
    public var confidence: FootprintConfidence
    public var reason: String

    public init(
        url: URL, location: FootprintLocation, sizeBytes: Int64,
        confidence: FootprintConfidence = .likely, reason: String = ""
    ) {
        self.url = url
        self.location = location
        self.sizeBytes = sizeBytes
        self.confidence = confidence
        self.reason = reason
    }
}

/// Files, findings, and recommendations staging a complete uninstall.
/// Read-only to build: the caller merges these into the review plan and the
/// standard SafetyAuditor → ActionExecutor pipeline executes them — this
/// service never touches the filesystem outside measuring sizes.
public struct StagedUninstall: Sendable {
    public var files: [FileRecord]
    public var findings: [Finding]
    public var recommendations: [Recommendation]

    public init(files: [FileRecord], findings: [Finding], recommendations: [Recommendation]) {
        self.files = files
        self.findings = findings
        self.recommendations = recommendations
    }
}

public enum ApplicationFootprintError: Error, LocalizedError, Sendable {
    case selfUninstallBlocked(String)

    public var errorDescription: String? {
        switch self {
        case .selfUninstallBlocked(let name):
            String(localized: "Refusing to stage an uninstall of the running app (\(name)).", comment: "Self-uninstall refusal")
        }
    }
}

/// Enumerates installed applications and measures each app's true footprint:
/// the .app bundle plus scattered data in known Library locations matched
/// by bundle identifier (exact, `.plist`, or `bundleID.*` prefix) or by exact
/// normalized app-name match. Matching is deliberately conservative —
/// substring matches are never used, so similarly-named folders belonging to
/// other apps are left alone.
///
/// All methods are read-only. Uninstall candidates are returned as staged
/// Trash-first recommendations that must flow through user approval,
/// SafetyAuditor, and ActionExecutor like any other plan action.
public actor ApplicationFootprintService {
    private let policy = PathSafetyPolicy()
    let fileManager: FileManager
    private let homeDirectoryOverride: URL?
    private let systemLibrary: URL
    let installedBundlesOverride: [URL]?
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "ApplicationFootprintService")

    /// - Parameters:
    ///   - systemLibraryOverride: stands in for `/Library` in tests.
    ///   - installedBundles: the other installed apps, for tests. Nil reads the standard app folders.
    public init(
        fileManager: FileManager = .default, homeDirectoryOverride: URL? = nil, systemLibraryOverride: URL? = nil,
        installedBundles: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectoryOverride = homeDirectoryOverride
        self.systemLibrary = systemLibraryOverride ?? URL(fileURLWithPath: "/Library", isDirectory: true)
        self.installedBundlesOverride = installedBundles
    }

    func isAllowed(_ record: FileRecord) -> Bool {
        if case .allow = policy.decide(target: record.url, isDirectory: record.kind == .directory) {
            return true
        }
        return false
    }

    /// Every .app bundle directly inside /Applications and ~/Applications,
    /// sorted by name, with bundle sizes measured via allocated-size walks.
    public func enumerateInstalledApplications() async -> [InstalledApplication] {
        let home = homeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        var apps: [InstalledApplication] = []
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children where child.pathExtension == "app" {
                if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                    continue
                }
                let bundleID = Bundle(url: child)?.bundleIdentifier
                let name = child.deletingPathExtension().lastPathComponent
                apps.append(InstalledApplication(
                    id: bundleID ?? "path:\(child.standardizedFileURL.path)",
                    name: name,
                    bundleURL: child.standardizedFileURL,
                    bundleIdentifier: bundleID,
                    bundleSizeBytes: Self.allocatedSize(of: child, fileManager: fileManager)
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Scattered footprint for an app: direct children of known Library
    /// locations matched by name, launch items that run the app, helpers those
    /// items start, and app-group containers named in the app's signature.
    /// Nested matches are ignored: a subfolder's name is not evidence.
    public func footprintItems(for app: InstalledApplication) async -> [ApplicationFootprintItem] {
        let home = homeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        func user(_ name: String) -> URL { library.appendingPathComponent(name, isDirectory: true) }
        func system(_ name: String) -> URL { systemLibrary.appendingPathComponent(name, isDirectory: true) }
        let nameLocations: [(FootprintLocation, URL)] = [
            (.caches, user("Caches")), (.preferences, user("Preferences")),
            (.preferences, user("Preferences/ByHost")),
            (.applicationSupport, user("Application Support")), (.logs, user("Logs")),
            (.httpStorages, user("HTTPStorages")), (.containers, user("Containers")),
            (.savedState, user("Saved Application State")), (.webKit, user("WebKit")),
            (.cookies, user("Cookies")), (.applicationScripts, user("Application Scripts")),
            (.systemCaches, system("Caches")), (.systemApplicationSupport, system("Application Support")),
            (.systemPreferences, system("Preferences")), (.systemLogs, system("Logs"))
        ]
        let others = otherApps(than: app, home: home)
        // Reading inside another app's container asks for consent without Full Disk Access.
        let readsContainers = FullDiskAccess.isGranted(home: home)
        var items: [ApplicationFootprintItem] = []
        for (location, directory) in nameLocations {
            for child in children(of: directory) {
                var match = Self.footprintMatch(entryName: child.lastPathComponent, app: app)
                if match == nil, location == .containers, readsContainers, Self.isUUID(child.lastPathComponent),
                    let id = app.bundleIdentifier?.lowercased(), containerOwner(child) == id {
                    match = (.certain, String(localized: "Container metadata names this app"))
                }
                guard let match,
                    !Self.belongsToOtherApp(child.lastPathComponent, app: app, others: others.map(\.id)) else { continue }
                items.append(item(child, location, match))
            }
        }
        items += groupContainers(for: app, in: user("Group Containers"), others: others)
        items += launchItems(for: app, library: library, others: others.map(\.id))
        return items.sorted { ($0.confidence, $0.sizeBytes) > ($1.confidence, $1.sizeBytes) }
    }

    func children(of directory: URL) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        // Symlinks are never staged: SafetyAuditor rejects destructive symlink actions.
        return entries.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true }
    }

    func item(
        _ url: URL, _ location: FootprintLocation, _ match: (FootprintConfidence, String)
    ) -> ApplicationFootprintItem {
        ApplicationFootprintItem(
            url: url.standardizedFileURL, location: location,
            sizeBytes: Self.allocatedSize(of: url, fileManager: fileManager),
            confidence: match.0, reason: match.1)
    }

    /// Launch agents and daemons whose label, associated bundle IDs, or
    /// program point at the app, plus the privileged helpers they start.
    private func launchItems(for app: InstalledApplication, library: URL, others: [String]) -> [ApplicationFootprintItem] {
        let folders: [(FootprintLocation, URL)] = [
            (.launchAgents, library.appendingPathComponent("LaunchAgents", isDirectory: true)),
            (.systemLaunchAgents, systemLibrary.appendingPathComponent("LaunchAgents", isDirectory: true)),
            (.systemLaunchDaemons, systemLibrary.appendingPathComponent("LaunchDaemons", isDirectory: true))
        ]
        var items: [ApplicationFootprintItem] = []
        var helperConfidence: [String: FootprintConfidence] = [:]
        let helpers = systemLibrary.appendingPathComponent("PrivilegedHelperTools", isDirectory: true)
        let shared = (FootprintConfidence.possible, String(localized: "Also used by another installed app"))
        for (location, folder) in folders {
            for plist in children(of: folder) where plist.pathExtension == "plist" {
                guard let job = NSDictionary(contentsOf: plist) as? [String: Any],
                    Self.launchJob(job, belongsTo: app) else { continue }
                let isShared = Self.launchJob(job, app: app, isSharedWith: others)
                items.append(item(
                    plist, location, isShared ? shared : (.certain, String(localized: "Launch item that runs this app"))))
                if let program = Self.program(of: job) {
                    // Resolve both sides: /var and /private/var name the same folder.
                    let resolved = URL(fileURLWithPath: program).resolvingSymlinksInPath()
                    if resolved.deletingLastPathComponent().path == helpers.resolvingSymlinksInPath().path {
                        helperConfidence[resolved.path] = isShared ? .possible : .certain
                    }
                }
            }
        }
        for helper in children(of: helpers) {
            if let confidence = helperConfidence[helper.resolvingSymlinksInPath().path] {
                items.append(item(helper, .privilegedHelperTools, confidence == .certain
                    ? (.certain, String(localized: "Helper started by this app's launch item")) : shared))
            } else if let match = Self.footprintMatch(entryName: helper.lastPathComponent, app: app),
                !Self.belongsToOtherApp(helper.lastPathComponent, app: app, others: others) {
                items.append(item(helper, .privilegedHelperTools, match))
            }
        }
        return items
    }

    /// Bundle ID recorded by containermanagerd for UUID-named containers.
    private func containerOwner(_ container: URL) -> String? {
        let metadata = container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        let plist = NSDictionary(contentsOf: metadata) as? [String: Any]
        return (plist?["MCMMetadataIdentifier"] as? String)?.lowercased()
    }

    /// Builds the staged uninstall for an app: FileRecords with real
    /// device/inode identity (so SafetyAuditor's TOCTOU checks can verify
    /// them), one high-risk bundle finding plus one medium-risk scattered-data
    /// finding, and Trash-first recommendations requiring confirmation.
    /// Throws when asked to stage the currently running app itself.
    public func stagedUninstall(for app: InstalledApplication, sessionID: String) async throws -> StagedUninstall {
        if app.bundleURL.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            throw ApplicationFootprintError.selfUninstallBlocked(app.name)
        }
        let footprint = await footprintItems(for: app)
        // Only sure matches the user can move are staged for Trash. Possible
        // matches and items that need administrator rights stay review-only.
        let scattered = footprint.filter { $0.confidence >= .likely && canTrash($0.url) }
        let reviewOnly = footprint.filter { $0.confidence < .likely || !canTrash($0.url) }
        var files: [FileRecord] = []
        var findings: [Finding] = []
        var recommendations: [Recommendation] = []

        // The bundle itself: high risk, always requires explicit confirmation
        // at the audit gate (set by the UI approve gesture).
        if let bundleRecord = makeRecord(url: app.bundleURL, sessionID: sessionID, sizeBytes: max(0, app.bundleSizeBytes)),
           isAllowed(bundleRecord) {
            files.append(bundleRecord)
            let findingID = UUID().uuidString
            findings.append(Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: .appLeftover,
                severity: .high,
                confidence: 0.9,
                bytesReclaimable: bundleRecord.sizeBytes,
                summary: String(localized: "Complete uninstall: \(app.name) app bundle (\(bundleRecord.sizeBytes.formattedByteCount))", comment: "App bundle uninstall finding"),
                evidence: ["path": bundleRecord.displayPath, "bundle_id": app.bundleIdentifier ?? "", "bytes": String(bundleRecord.sizeBytes)],
                targetFileIDs: [bundleRecord.id]
            ))
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .moveToTrash,
                targetFileIDs: [bundleRecord.id],
                confidence: 0.9,
                risk: .high,
                reason: String(localized: "Move the \(app.name) app bundle to Trash. The app stops working once trashed; restore from Trash or reinstall to recover. Review before approving.", comment: "App bundle uninstall recommendation"),
                expectedBytesReclaimed: bundleRecord.sizeBytes,
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "app_uninstall_bundle"
            ))
        }

        // Scattered data: one finding grouping every matched Library item so
        // the user approves the whole footprint in a single gesture.
        var scatteredRecords: [FileRecord] = []
        for item in scattered {
            guard let record = makeRecord(url: item.url, sessionID: sessionID, sizeBytes: max(0, item.sizeBytes)),
                  isAllowed(record) else { continue }
            scatteredRecords.append(record)
        }
        if !scatteredRecords.isEmpty {
            let bytes = scatteredRecords.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let findingID = UUID().uuidString
            let systemCount = scattered.filter(\.location.isSystemWide).count
            let scopeNote = systemCount > 0
                ? String(localized: " \(systemCount) item(s) live in system-wide locations shared with the OS or other users. Review those paths carefully.", comment: "System-wide footprint warning suffix")
                : ""
            findings.append(Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: .appLeftover,
                severity: .medium,
                confidence: 0.75,
                bytesReclaimable: bytes,
                summary: String(localized: "Complete uninstall: \(app.name) scattered data (\(scatteredRecords.count) locations, \(bytes.formattedByteCount))", comment: "App scattered-data uninstall finding"),
                evidence: ["bundle_id": app.bundleIdentifier ?? "", "locations": scattered.map(\.location.rawValue).joined(separator: ","), "bytes": String(bytes)],
                targetFileIDs: scatteredRecords.map(\.id)
            ))
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .moveToTrash,
                targetFileIDs: scatteredRecords.map(\.id),
                confidence: 0.75,
                risk: .medium,
                reason: String(localized: "Move \(scatteredRecords.count) leftover data locations for \(app.name) (caches, preferences, logs) to Trash. Rebuildable or regenerable data; preferences are lost unless restored from Trash.\(scopeNote)", comment: "App scattered-data uninstall recommendation"),
                expectedBytesReclaimed: bytes,
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "app_uninstall_scattered"
            ))
            files.append(contentsOf: scatteredRecords)
        }

        if let review = reviewOnlyGroup(reviewOnly, app: app, sessionID: sessionID) {
            files.append(contentsOf: review.files)
            findings.append(contentsOf: review.findings)
            recommendations.append(contentsOf: review.recommendations)
        }

        if files.isEmpty {
            logger.info("No uninstallable footprint for \(app.name, privacy: .public): bundle missing or protected.")
        }
        return StagedUninstall(files: files, findings: findings, recommendations: recommendations)
    }

    /// The user can move the item only when its parent folder is writable.
    private func canTrash(_ url: URL) -> Bool {
        fileManager.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    // MARK: - Matching

    // MARK: - Records and sizes

    /// Builds an audit-ready FileRecord: real device/inode identity for the
    /// SafetyAuditor TOCTOU checks, fresh risk flags, and Trash capability.
    /// Returns nil when the target vanished mid-enumeration.
    func makeRecord(url: URL, sessionID: String, sizeBytes: Int64) -> FileRecord? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let directory = isDirectory.boolValue
        let isPackage = url.pathExtension == "app"
        let kind: FileKind = isPackage ? .package : (directory ? .directory : .regularFile)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let device = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        let inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        let standardized = url.standardizedFileURL
        return FileRecord(
            id: UUID().uuidString,
            scanSessionID: sessionID,
            source: .local,
            url: standardized,
            displayPath: standardized.path,
            fileName: standardized.lastPathComponent,
            fileExtension: standardized.pathExtension.isEmpty ? nil : standardized.pathExtension.lowercased(),
            utiDescription: nil,
            kind: kind,
            sizeBytes: sizeBytes,
            createdAt: nil,
            modifiedAt: nil,
            lastOpenedAt: nil,
            owner: nil,
            permissions: nil,
            isSymlink: false,
            symlinkTarget: nil,
            isPackage: isPackage,
            isCloudPlaceholder: false,
            cloudProvider: policy.cloudProvider(for: standardized),
            finderTags: [],
            spotlightMetadata: [:],
            riskFlags: policy.riskFlags(for: standardized, isDirectory: directory || isPackage),
            identity: FileIdentity(deviceIdentifier: device, inodeIdentifier: inode, resourceIdentifier: nil),
            capabilities: [.canMove, .canTrash, .canRestore]
        )
    }

    /// Allocated-size walk (files sum `totalFileAllocatedSize`, falling back to
    /// logical size). Symlinked subtrees are skipped so linked data outside the
    /// app is never attributed to it.
    nonisolated static func allocatedSize(of url: URL, fileManager: FileManager) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
