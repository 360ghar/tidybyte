import Foundation

public enum PermissionError: Error, LocalizedError, Sendable {
    case noSelectedFolders
    case folderUnavailable(URL)

    public var errorDescription: String? {
        switch self {
        case .noSelectedFolders:
            String(localized: "Select at least one folder before scanning.", comment: "Permission error when no folders are selected")
        case .folderUnavailable(let url):
            String(localized: "The folder is not readable: \(url.path)", comment: "Permission error for an unreadable folder")
        }
    }
}

/// Full Disk Access cannot be queried directly. Opening a file that only
/// Full Disk Access unlocks is the reliable check: a permission error means
/// no access, a missing file means try the next probe.
public enum FullDiskAccess {
    public static func isGranted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let probes = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Mail")
        ]
        for probe in probes {
            switch canOpen(probe) {
            case .some(let granted): return granted
            case .none: continue
            }
        }
        return false
    }

    /// Other apps' containers. Without Full Disk Access, reading inside them
    /// asks the person for consent, so scans do not enter them.
    public static func closedAppDataFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<String> {
        guard !isGranted(home: home) else { return [] }
        return Set(["Library/Containers", "Library/Group Containers"].map {
            home.appendingPathComponent($0, isDirectory: true).standardizedFileURL.path
        })
    }

    /// true = opened, false = permission denied, nil = not there.
    static func canOpen(_ url: URL) -> Bool? {
        let descriptor = open(url.path, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }
        return errno == ENOENT ? nil : false
    }
}

public actor PermissionManager {
    private let fileManager: FileManager
    private let policy: PathSafetyPolicy
    /// Override for the user home directory. Tests point this at a temp directory
    /// so system-clean section roots resolve under a controlled fixture.
    private let homeDirectoryOverride: URL?

    public init(fileManager: FileManager = .default, policy: PathSafetyPolicy = PathSafetyPolicy(), homeDirectoryOverride: URL? = nil) {
        self.fileManager = fileManager
        self.policy = policy
        self.homeDirectoryOverride = homeDirectoryOverride
    }

    private var home: URL { homeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser }

    public func roots(for mode: ScanMode, selectedFolders: [URL]) throws -> [URL] {
        switch mode {
        case .selectedFolders:
            guard !selectedFolders.isEmpty else {
                throw PermissionError.noSelectedFolders
            }
            return try selectedFolders.map(validateReadableDirectory)
        case .homeFolder:
            return [try validateReadableDirectory(home)]
        case .developerCleanup:
            // Skip unreadable roots instead of aborting the whole scan: one
            // permission-broken candidate (e.g. ~/.m2) must not kill the run.
            return developerRoots().compactMap { try? validateReadableDirectory($0) }
        case .deepSystem, .userEssentials, .finderMetadata, .macOSSystemCaches,
             .sandboxedAppCaches, .browsers, .cloudStorage, .officeApps,
             .developerTools, .devApplications, .vmTools, .applicationSupport,
             .uninstalledAppData, .appleSiliconUpdates, .iosBackups,
             .timeMachineBackups, .largeFiles:
            // mo clean sections scan well-known paths directly. Unreadable or
            // missing paths are silently skipped — they often require Full Disk
            // Access, which the user may not have granted.
            guard let section = mode.systemCleanSection else { return [] }
            return section.knownPaths(home: home)
                .filter { fileManager.fileExists(atPath: $0.path) }
                .compactMap { try? validateReadableDirectory($0) }
        }
    }

    public func permissionsSnapshot(for roots: [URL], mode: ScanMode) -> String {
        let readable = roots.filter { url in
            fileManager.isReadableFile(atPath: url.path)
        }
        let names = readable.map(\.path).joined(separator: ", ")
        switch mode {
        case .selectedFolders:
            return "Selected-folder grants: \(names)"
        case .homeFolder:
            return "Home-folder scan. Full Disk Access may be required for protected folders. Readable roots: \(names)"
        case .developerCleanup:
            return "Developer cleanup scan. Readable developer roots: \(names)"
        case .deepSystem, .userEssentials, .finderMetadata, .macOSSystemCaches,
             .sandboxedAppCaches, .browsers, .cloudStorage, .officeApps,
             .developerTools, .devApplications, .vmTools, .applicationSupport,
             .uninstalledAppData, .appleSiliconUpdates, .iosBackups,
             .timeMachineBackups, .largeFiles:
            return "System clean section scan. Full Disk Access may be required for some paths. Readable roots: \(names)"
        }
    }

    public func mountedVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]
        let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Volume(
                id: values?.volumeUUIDString ?? url.path,
                mountURL: url,
                volumeName: values?.volumeName ?? url.lastPathComponent,
                volumeUUID: values?.volumeUUIDString,
                isInternal: values?.volumeIsInternal ?? false,
                isExternal: !(values?.volumeIsInternal ?? true),
                isNetwork: !(values?.volumeIsLocal ?? true),
                isCloudSynced: policy.cloudProvider(for: url) != nil,
                capacityBytes: values?.volumeTotalCapacity.map(Int64.init),
                availableBytes: values?.volumeAvailableCapacity.map(Int64.init),
                lastSeenAt: Date()
            )
        }
    }

    private func validateReadableDirectory(_ url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: url.path) else {
            throw PermissionError.folderUnavailable(url)
        }
        return url.standardizedFileURL
    }

    private func developerRoots() -> [URL] {
        let candidates = [
            home.appendingPathComponent("Developer", isDirectory: true),
            home.appendingPathComponent("Projects", isDirectory: true),
            home.appendingPathComponent("Code", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Library/Developer", isDirectory: true),
            home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true),
            home.appendingPathComponent(".cache", isDirectory: true),
            home.appendingPathComponent(".npm", isDirectory: true),
            home.appendingPathComponent(".pnpm-store", isDirectory: true),
            home.appendingPathComponent(".yarn", isDirectory: true),
            home.appendingPathComponent(".cargo", isDirectory: true),
            home.appendingPathComponent(".gradle", isDirectory: true),
            home.appendingPathComponent(".m2", isDirectory: true),
            home.appendingPathComponent(".local", isDirectory: true)
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }
}
