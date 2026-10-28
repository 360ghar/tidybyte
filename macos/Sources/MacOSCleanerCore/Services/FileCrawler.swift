import Darwin
import Foundation
import os

/// Walks scan roots and records metadata for every item. Top-level folders
/// of each root are crawled in parallel (at most `maxParallelFolders` at a
/// time), and each item costs one `lstat` plus a package check for folders
/// with an extension. Finder tags, owners, and type names are read later,
/// only for the items a person inspects.
///
/// Memory stays bounded. Bulk folders that no review lists file by file
/// (version control, dependency, build, and tool-cache trees) become one
/// record each that carries the total size of their contents, and after
/// `maxRecords` records every further folder is summarized the same way and
/// every further loose file is folded into the size of its folder. Only files
/// of `largeFileBytes` or more keep a record past the budget.
public actor FileCrawler {
    private let fileManager: FileManager
    private let policy: PathSafetyPolicy
    private let maxRecords: Int
    static let maxParallelFolders = 8
    /// About 1.8 KB each at the crawl's peak, so roughly 1.8 GB for a full budget.
    public static let defaultMaxRecords = 1_000_000
    /// Files this large always get a record of their own, even past the record
    /// budget and inside summarized folders, so the large-file review sees them.
    public static let largeFileBytes: Int64 = 1_000_000_000
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "FileCrawler")

    public init(
        fileManager: FileManager = .default,
        policy: PathSafetyPolicy = PathSafetyPolicy(),
        maxRecords: Int = FileCrawler.defaultMaxRecords
    ) {
        self.fileManager = fileManager
        self.policy = policy
        self.maxRecords = maxRecords
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
        // Personal folders first, then dot-folders, then ~/Library. Each tier
        // finishes before the next starts, so if the record budget runs out, it
        // runs out where per-file detail matters least.
        let policy = policy
        let budget = RecordBudget(limit: maxRecords, used: records.count)
        for tier in 0...Self.lastCrawlTier {
            await withTaskGroup(of: ([FileRecord], Int).self) { group in
                var pending = folders.filter { Self.crawlOrder($0) == tier }[...]
                func addNext() {
                    guard let folder = pending.popFirst() else { return }
                    group.addTask {
                        Self.crawlFolder(folder, sessionID: sessionID, policy: policy, closed: closed, budget: budget)
                    }
                }
                for _ in 0..<Self.maxParallelFolders { addNext() }
                for await (folderRecords, folderErrors) in group {
                    records += folderRecords
                    errors += folderErrors
                    addNext()
                }
            }
        }
        if budget.isSpent {
            Self.logger.warning("Crawl reached \(self.maxRecords) records; later folders are summarized as one record each.")
        }
        // Sorted in place: a sorted copy would hold every record twice at the peak.
        records.sort { $0.displayPath < $1.displayPath }
        return (records, errors)
    }

    static let lastCrawlTier = 2

    static func crawlOrder(_ folder: URL) -> Int {
        let name = folder.lastPathComponent
        if name == "Library" { return lastCrawlTier }
        return name.hasPrefix(".") ? 1 : 0
    }

    private struct RootExpansion {
        var records: [FileRecord] = []
        var errors = 0
        var folders: [URL] = []
    }

    /// Counts records across the parallel folder tasks.
    final class RecordBudget: Sendable {
        private let state: OSAllocatedUnfairLock<Int>
        private let limit: Int

        init(limit: Int, used: Int = 0) {
            self.limit = limit
            state = OSAllocatedUnfairLock(initialState: used)
        }

        /// Takes one record from the budget. False once the budget is spent.
        func take() -> Bool {
            state.withLock { used in
                guard used < limit else { return false }
                used += 1
                return true
            }
        }

        var isSpent: Bool { state.withLock { $0 >= limit } }
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
        _ folder: URL, sessionID: String, policy: PathSafetyPolicy, closed: Set<String>, budget: RecordBudget
    ) -> ([FileRecord], Int) {
        var output: [FileRecord] = []
        var errors = 0
        if let record = makeRecord(for: folder, sessionID: sessionID, policy: policy) {
            // The budget may be spent before this folder starts; it then costs one record.
            guard budget.take(), !rollsUp(folder) else {
                let summary = rolledUp(record, sessionID: sessionID, policy: policy, closed: closed)
                return (summary.records, summary.errors)
            }
            output.append(record)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [], options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                logger.warning("Crawler skipped \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            })
        else { return (output, 1) }
        // One autorelease pool per item. The loop is one synchronous job, so without
        // it every URL, path, and resource value the enumerator autoreleases stays
        // alive until the whole folder is done: about 2.5 KB per item.
        // Loose files past the budget: their bytes and count, by parent folder.
        var overflow: [String: (bytes: Int64, items: Int)] = [:]
        var finished = false
        while !finished {
            autoreleasepool {
                // Cooperative cancellation: the orchestrator discards partial results.
                guard !Task.isCancelled, let url = enumerator.nextObject() as? URL else {
                    finished = true
                    return
                }
                let skipped = policy.shouldSkipTraversal(of: url) || closed.contains(url.path)
                if skipped { enumerator.skipDescendants() }
                guard let record = makeRecord(for: url, sessionID: sessionID, policy: policy) else {
                    errors += 1
                    return
                }
                let withinBudget = budget.take()
                if record.kind == .directory, !skipped, !withinBudget || rollsUp(url) {
                    enumerator.skipDescendants()
                    let summary = rolledUp(record, sessionID: sessionID, policy: policy, closed: closed)
                    output += summary.records
                    errors += summary.errors
                } else if withinBudget || record.kind == .directory
                    || (record.kind == .regularFile && record.sizeBytes >= largeFileBytes) {
                    output.append(record)
                } else {
                    let parent = url.deletingLastPathComponent().standardizedFileURL.path
                    overflow[parent, default: (0, 0)].bytes += record.sizeBytes
                    overflow[parent, default: (0, 0)].items += 1
                }
            }
        }
        foldOverflow(overflow, into: &output)
        return (output, errors)
    }

    /// Adds the bytes of loose files that got no record to their folder's
    /// record, which then reads as a summarized folder. A folder with no record
    /// of its own (a package, a skipped path) passes its share to the crawled
    /// folder at the top.
    private static func foldOverflow(_ overflow: [String: (bytes: Int64, items: Int)], into output: inout [FileRecord]) {
        guard !overflow.isEmpty else { return }
        var left = overflow
        for index in output.indices where output[index].kind == .directory {
            guard let share = left.removeValue(forKey: output[index].url.path) else { continue }
            output[index].sizeBytes += share.bytes
            output[index].rolledUpItemCount = (output[index].rolledUpItemCount ?? 0) + share.items
        }
        guard !left.isEmpty, !output.isEmpty, output[0].kind == .directory else { return }
        output[0].sizeBytes += left.values.reduce(0) { $0 + $1.bytes }
        output[0].rolledUpItemCount = (output[0].rolledUpItemCount ?? 0) + left.values.reduce(0) { $0 + $1.items }
    }

    // MARK: - Summarized folders

    /// Folders whose contents no review lists one by one. Each name is specific
    /// enough that a folder of personal documents will not carry it. Tool homes
    /// that hold a cache folder (~/.gradle/caches, ~/.yarn/berry/cache) are not
    /// listed: their cache folders are cleanup candidates of their own.
    static let rolledUpFolderNames: Set<String> = [
        "node_modules", ".git", ".hg", ".svn",
        "deriveddata", ".build", ".swiftpm",
        ".venv", "venv", ".tox", "__pycache__", "site-packages",
        ".mypy_cache", ".pytest_cache", ".ruff_cache",
        ".next", ".nuxt", ".turbo", ".parcel-cache", ".angular", ".dart_tool",
        ".m2", ".npm", ".pnpm-store", "pnpm-store", ".rustup", ".pub-cache", ".dartserver", ".cocoapods"
    ]

    /// A cache folder's entries are reviewed one per entry, never file by file.
    private static let cacheFolderNames: Set<String> = ["caches", "cache", ".cache"]

    /// Build output names that can also name personal folders, so they are
    /// summarized only beside a build manifest.
    private static let projectBuildFolderNames: Set<String> = ["build", "dist", "target", "out", ".gradle"]

    /// Build-tool manifests only. A README or a .git folder does not make a
    /// folder of documents a project whose "build" folder can be summarized.
    private static let buildManifests = [
        "package.json", "Package.swift", "Cargo.toml", "go.mod", "pom.xml", "build.gradle", "build.gradle.kts",
        "settings.gradle", "settings.gradle.kts", "pubspec.yaml", "project.yml", "CMakeLists.txt", "pyproject.toml"
    ]

    /// True for a folder that is crawled as one summarized record: a bulk folder
    /// by name, an entry of a cache folder, one simulator device, one Device
    /// Support version, or a build output folder of a project.
    static func rollsUp(_ folder: URL) -> Bool {
        if rolledUpFolderNames.contains(folder.lastPathComponent.lowercased()) { return true }
        let parent = folder.deletingLastPathComponent()
        let parentName = parent.lastPathComponent.lowercased()
        if cacheFolderNames.contains(parentName) || parentName.hasSuffix("devicesupport") { return true }
        if parentName == "devices", parent.deletingLastPathComponent().lastPathComponent.lowercased() == "coresimulator" {
            return true
        }
        // pnpm's global content store (~/Library/pnpm/store): hard-linked package files.
        if parentName == "pnpm", folder.lastPathComponent.lowercased() == "store" { return true }
        return projectBuildFolderNames.contains(folder.lastPathComponent.lowercased()) && isBuildProjectRoot(parent)
    }

    static func isBuildProjectRoot(_ folder: URL) -> Bool {
        if buildManifests.contains(where: { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }) {
            return true
        }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return entries.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    /// The folder's record with the total size and item count of its contents.
    /// Its date becomes the newest change inside, so age rules (old files,
    /// leftovers unchanged for 30 days) never see a summarized folder as older
    /// than its newest file.
    ///
    /// A cache folder directly inside (node_modules/.cache) is a cleanup
    /// candidate of its own, so it gets its own summarized record and its size
    /// stays out of the parent's total. A file of `largeFileBytes` or more also
    /// keeps a record of its own, and its size stays out of the total.
    ///
    /// A file with other hard links adds nothing to the size, because trashing
    /// it frees nothing (see `ReclaimableBytes`). `errors` counts the entries
    /// that could not be read, which the total then leaves out.
    static func rolledUp(
        _ folder: FileRecord, sessionID: String, policy: PathSafetyPolicy, closed: Set<String>
    ) -> (records: [FileRecord], errors: Int) {
        var record = folder
        var kept: [FileRecord] = []
        var bytes: Int64 = 0
        var items = 0
        var errors = 0
        var newest = folder.modifiedAt ?? .distantPast
        let unreadable = ErrorCount()
        if let enumerator = FileManager.default.enumerator(
            at: folder.url, includingPropertiesForKeys: [], options: [], errorHandler: { url, error in
                logger.warning("Crawler skipped \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                unreadable.value += 1
                return true
            }) {
            var finished = false
            while !finished {
                autoreleasepool {
                    guard !Task.isCancelled, let url = enumerator.nextObject() as? URL else {
                        finished = true
                        return
                    }
                    if policy.shouldSkipTraversal(of: url) || closed.contains(url.path) {
                        enumerator.skipDescendants()
                        return
                    }
                    if enumerator.level == 1, cacheFolderNames.contains(url.lastPathComponent.lowercased()),
                        let child = makeRecord(for: url, sessionID: sessionID, policy: policy), child.kind == .directory {
                        enumerator.skipDescendants()
                        let summary = rolledUp(child, sessionID: sessionID, policy: policy, closed: closed)
                        kept += summary.records
                        errors += summary.errors
                        return
                    }
                    var info = stat()
                    guard lstat(url.path, &info) == 0 else {
                        logger.warning("Metadata unavailable for \(url.path, privacy: .public)")
                        errors += 1
                        return
                    }
                    let isRegular = info.st_mode & S_IFMT == S_IFREG
                    if isRegular, Int64(info.st_size) >= largeFileBytes,
                        let large = makeRecord(for: url, sessionID: sessionID, policy: policy) {
                        kept.append(large)
                    } else {
                        items += 1
                        if info.st_mode & S_IFMT != S_IFDIR, info.st_nlink <= 1 { bytes += Int64(info.st_size) }
                    }
                    newest = max(newest, date(info.st_mtimespec))
                }
            }
        }
        record.sizeBytes = bytes
        record.rolledUpItemCount = items
        record.modifiedAt = newest
        return ([record] + kept, errors + unreadable.value)
    }

    /// Counts unreadable entries from the enumerator's error handler.
    private final class ErrorCount {
        var value = 0
    }

    // MARK: - Records

    /// One shared set for every crawled record, so a record does not allocate its own.
    private static let crawledCapabilities: Set<ProviderCapability> = [.canMove, .canTrash, .canRestore, .canTag]

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
            capabilities: crawledCapabilities)
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
