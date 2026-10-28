import Darwin
import Foundation
import os

/// Walks scan roots and records metadata for every item. Top-level folders
/// of each root are crawled in parallel (at most `maxParallelFolders` at a
/// time), and each item costs one `lstat` plus a package check for folders
/// with an extension. Finder tags, owners, and type names are read later,
/// only for the items a person inspects.
public actor FileCrawler {
    private let fileManager: FileManager
    private let policy: PathSafetyPolicy
    static let maxParallelFolders = 8
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "FileCrawler")

    public init(fileManager: FileManager = .default, policy: PathSafetyPolicy = PathSafetyPolicy()) {
        self.fileManager = fileManager
        self.policy = policy
    }

    public func crawl(rootURLs: [URL], sessionID: String) async -> ([FileRecord], Int) {
        var records: [FileRecord] = []
        var errors = 0
        var folders: [URL] = []
        let closed = FullDiskAccess.closedAppDataFolders()
        for root in rootURLs {
            let expansion = Self.expandRoot(root, sessionID: sessionID, policy: policy, closed: closed)
            records += expansion.records
            errors += expansion.errors
            folders += expansion.folders
        }
        let policy = policy
        await withTaskGroup(of: ([FileRecord], Int).self) { group in
            var pending = folders[...]
            func addNext() {
                guard let folder = pending.popFirst() else { return }
                group.addTask { Self.crawlFolder(folder, sessionID: sessionID, policy: policy, closed: closed) }
            }
            for _ in 0..<Self.maxParallelFolders { addNext() }
            for await (folderRecords, folderErrors) in group {
                records += folderRecords
                errors += folderErrors
                addNext()
            }
        }
        return (records.sorted { $0.displayPath < $1.displayPath }, errors)
    }

    private struct RootExpansion {
        var records: [FileRecord] = []
        var errors = 0
        var folders: [URL] = []
    }

    /// Records the root and its direct non-folder children; returns the child
    /// folders so they can be crawled in parallel. A root that is a package is
    /// entered: the person chose it. Symlinks are never followed, roots included.
    private static func expandRoot(
        _ root: URL, sessionID: String, policy: PathSafetyPolicy, closed: Set<String>
    ) -> RootExpansion {
        // A protected root (.ssh, SIP path, Trash) is never crawled at all.
        if policy.shouldSkipTraversal(of: root) || closed.contains(root.standardizedFileURL.path) {
            logger.warning("Skipping protected scan root: \(root.path, privacy: .public)")
            return RootExpansion()
        }
        guard let rootRecord = makeRecord(for: root, sessionID: sessionID, policy: policy) else {
            logger.error("Unreadable scan root: \(root.path, privacy: .public)")
            return RootExpansion(errors: 1)
        }
        guard rootRecord.kind == .directory || rootRecord.kind == .package else {
            return RootExpansion(records: [rootRecord])
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [])
        else {
            logger.error("Unreadable scan root: \(root.path, privacy: .public)")
            return RootExpansion(errors: 1)
        }
        var expansion = RootExpansion(records: [rootRecord])
        for child in children {
            guard let record = makeRecord(for: child, sessionID: sessionID, policy: policy) else {
                expansion.errors += 1
                continue
            }
            if record.kind == .directory, !policy.shouldSkipTraversal(of: child), !closed.contains(child.path) {
                expansion.folders.append(child)
            } else {
                expansion.records.append(record)
            }
        }
        return expansion
    }

    /// The folder itself plus everything below it, packages not descended.
    private static func crawlFolder(
        _ folder: URL, sessionID: String, policy: PathSafetyPolicy, closed: Set<String>
    ) -> ([FileRecord], Int) {
        var output: [FileRecord] = []
        var errors = 0
        if let record = makeRecord(for: folder, sessionID: sessionID, policy: policy) { output.append(record) }
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [], options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                logger.warning("Crawler skipped \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            })
        else { return (output, 1) }
        while let url = enumerator.nextObject() as? URL {
            // Cooperative cancellation: the orchestrator discards partial results.
            if Task.isCancelled { break }
            if policy.shouldSkipTraversal(of: url) || closed.contains(url.path) { enumerator.skipDescendants() }
            guard let record = makeRecord(for: url, sessionID: sessionID, policy: policy) else {
                errors += 1
                continue
            }
            output.append(record)
        }
        return (output, errors)
    }

    static func makeRecord(for url: URL, sessionID: String, policy: PathSafetyPolicy) -> FileRecord? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            logger.warning("Metadata unavailable for \(url.path, privacy: .public)")
            return nil
        }
        let standardized = url.standardizedFileURL
        let type = info.st_mode & S_IFMT
        let isSymlink = type == S_IFLNK
        let isDirectory = type == S_IFDIR
        // Package lookup goes through Launch Services; only folders with an extension can be packages.
        let isPackage = isDirectory && !url.pathExtension.isEmpty
            && (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
        let kind: FileKind = isSymlink ? .symlink
            : isPackage ? .package
            : isDirectory ? .directory
            : type == S_IFREG ? .regularFile : .other
        let size: Int64 = kind == .directory ? 0 : Int64(info.st_size)
        let modified = date(info.st_mtimespec), cloudProvider = policy.cloudProvider(for: url)
        var record = FileRecord(
            id: StableFileID.forStandardizedPath(standardized.path, sizeBytes: size, modifiedAt: modified),
            scanSessionID: sessionID,
            source: source(for: cloudProvider),
            url: standardized,
            displayPath: standardized.path,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased(),
            utiDescription: nil,
            kind: kind,
            sizeBytes: size,
            createdAt: date(info.st_birthtimespec),
            modifiedAt: modified,
            lastOpenedAt: date(info.st_atimespec),
            owner: nil,
            permissions: String(info.st_mode & 0o7777, radix: 8),
            isSymlink: isSymlink,
            symlinkTarget: isSymlink ? symlinkTarget(of: url) : nil,
            isPackage: isPackage,
            isCloudPlaceholder: isPlaceholder(url, flags: info.st_flags, cloudProvider: cloudProvider),
            cloudProvider: cloudProvider,
            finderTags: [],
            spotlightMetadata: [:],
            riskFlags: policy.riskFlags(for: url, isDirectory: isDirectory),
            identity: FileIdentity(
                deviceIdentifier: UInt64(UInt32(bitPattern: info.st_dev)),
                inodeIdentifier: info.st_ino,
                resourceIdentifier: nil,
                // A folder's size and mtime change whenever its children do; device and inode identify it.
                sizeBytes: kind == .directory ? nil : size,
                modifiedAt: kind == .directory ? nil : modified),
            capabilities: [.canMove, .canTrash, .canRestore, .canTag])
        record.linkCount = Int(info.st_nlink)
        return record
    }

    /// Dataless files are cloud placeholders; other cloud paths ask the provider.
    private static func isPlaceholder(_ url: URL, flags: UInt32, cloudProvider: String?) -> Bool {
        if flags & UInt32(SF_DATALESS) != 0 { return true }
        guard cloudProvider != nil,
            let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        else { return false }
        return values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current
    }

    private static func symlinkTarget(of url: URL) -> URL? {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path))
            .map { URL(fileURLWithPath: $0, relativeTo: url.deletingLastPathComponent()).standardizedFileURL }
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    private static func source(for provider: String?) -> FileSource {
        switch provider {
        case "iCloud": .iCloudLocal
        case "Google Drive": .googleDriveLocal
        case "Dropbox": .dropboxLocal
        case "OneDrive": .oneDriveLocal
        default: .local
        }
    }
}
