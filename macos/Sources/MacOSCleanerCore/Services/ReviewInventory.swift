import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

public enum ReviewSafety {
    public static var userHome: URL {
        FileManager.default.homeDirectory(forUser: NSUserName()) ?? FileManager.default.homeDirectoryForCurrentUser
    }

    public static func contains(_ url: URL, in root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
    }

    public static func isAllowed(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let resolved = parent.appendingPathComponent(url.lastPathComponent).standardizedFileURL
        let paths = [url.standardizedFileURL, resolved]
        let forbidden = [
            "/System", "/Library", "/Applications", "/bin", "/sbin", "/usr", "/private/etc",
            userHome.appendingPathComponent("Library").path
        ]
        return paths.allSatisfy { candidate in
            let lower = candidate.path.lowercased()
            let components = candidate.pathComponents.dropFirst()
            guard !components.contains(where: { $0.hasPrefix(".") }) else { return false }
            guard
                !components.contains(where: {
                    [
                        "app", "photoslibrary", "photolibrary", "musiclibrary", "migratedphotolibrary",
                        "aplibrary", "photoboothlibrary", "imovielibrary", "fcpbundle"
                    ].contains(
                        URL(fileURLWithPath: $0).pathExtension.lowercased())
                })
            else { return false }
            return !forbidden.contains { lower == $0.lowercased() || lower.hasPrefix($0.lowercased() + "/") }
        }
    }

    public static func identity(at url: URL) throws -> FileIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw CleanupError.message(String(localized: "The file is no longer available: \(url.lastPathComponent)"))
        }
        return FileIdentity(
            deviceIdentifier: UInt64(info.st_dev), inodeIdentifier: UInt64(info.st_ino),
            resourceIdentifier: nil, sizeBytes: Int64(info.st_size),
            modifiedAt: Date(
                timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                    + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000))
    }

    public static func verify(_ item: ReviewItem) throws {
        guard let url = item.url, let root = item.root, item.canChange, isAllowed(url),
            contains(url, in: root),
            contains(url.deletingLastPathComponent().resolvingSymlinksInPath(), in: root.resolvingSymlinksInPath()),
            let expected = item.identity, try identity(at: url) == expected
        else {
            throw CleanupError.message(
                String(localized: "The file changed or is outside the approved scope. Scan again."))
        }
        if item.isPackage {
            let current = try packageSummary(url)
            guard current.version == item.packageVersion, current.downloaded else {
                throw CleanupError.message(String(localized: "The document package changed. Scan again."))
            }
        }
        try validateDestination(root)
    }

    public static func validateDestination(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .volumeIsLocalKey])
        guard isAllowed(url), isAllowed(url.resolvingSymlinksInPath()), values.isDirectory == true,
            values.volumeIsLocal == true, PathSafetyPolicy().cloudProvider(for: url) == nil
        else {
            throw CleanupError.message(
                String(localized: "Choose a local folder outside protected and cloud locations."))
        }
    }

    public static func uniqueOutput(in folder: URL, name: String) -> URL {
        let file = URL(fileURLWithPath: name)
        let base = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var result = folder.appendingPathComponent(file.lastPathComponent)
        var number = 2
        while (try? identity(at: result)) != nil {
            result = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return result
    }
    /// Reserve a new file before passing it to a media writer. Never follow a pre-existing link.
    public static func reserveOutput(in folder: URL, name: String) throws -> URL {
        for _ in 0..<100 {
            let output = uniqueOutput(in: folder, name: name)
            let descriptor = open(output.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            if descriptor >= 0 {
                close(descriptor)
                return output
            }
            if errno != EEXIST { break }
        }
        throw CleanupError.message(String(localized: "Cannot create a unique output in this folder."))
    }

    public struct PackageSummary {
        public let bytes: Int64
        public let version: String
        public let downloaded: Bool
    }
    public static func packageSummary(_ url: URL) throws -> PackageSummary {
        guard let entries = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            throw CleanupError.message(String(localized: "Cannot read the document package."))
        }
        var bytes: Int64 = 0
        var parts: [String] = []
        var downloaded = true
        while let child = entries.nextObject() as? URL {
            try Task.checkCancellation()
            var info = stat()
            guard lstat(child.path, &info) == 0 else {
                throw CleanupError.message(String(localized: "The document package is no longer available."))
            }
            if (info.st_mode & S_IFMT) != S_IFDIR { bytes += Int64(info.st_size) }
            downloaded = downloaded && (info.st_flags & UInt32(SF_DATALESS)) == 0
            let relative = child.path.dropFirst(url.path.count)
            parts.append(
                "\(relative)|\(info.st_ino)|\(info.st_size)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)")
        }
        let hash = SHA256.hash(data: Data(parts.sorted().joined(separator: "\n").utf8))
        return PackageSummary(
            bytes: bytes, version: hash.map { String(format: "%02x", $0) }.joined(), downloaded: downloaded)
    }

}

public actor FolderAccess {
    private let store: SQLiteStore
    public init(store: SQLiteStore) { self.store = store }

    public func grant(_ url: URL) async throws {
        guard ReviewSafety.isAllowed(url), ReviewSafety.isAllowed(url.resolvingSymlinksInPath()) else {
            throw CleanupError.message(String(localized: "This folder is protected and cannot be scanned."))
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        try await store.saveCleanupState(data, key: "grant:" + url.standardizedFileURL.path)
    }

    public func acquire(_ url: URL) async throws -> URL {
        if let data = try await store.loadCleanupState(Data.self, key: "grant:" + url.standardizedFileURL.path) {
            var stale = false
            let resolved = try URL(
                resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                relativeTo: nil, bookmarkDataIsStale: &stale)
            _ = resolved.startAccessingSecurityScopedResource()
            if stale {
                try await grant(resolved)
                let renewed = try resolved.bookmarkData(options: .withSecurityScope)
                try await store.saveCleanupState(renewed, key: "grant:" + url.standardizedFileURL.path)
            }
            return resolved
        }
        if DistributionChannel.supportsAdvanced { return url }
        throw CleanupError.message(String(localized: "Choose \(url.lastPathComponent) to grant folder access."))
    }
}

public actor ReviewInventory {
    private let access: FolderAccess
    public init(access: FolderAccess) { self.access = access }

    public func scan(
        _ scope: ReviewScope,
        progress: @Sendable (CleanupProgress) async -> Void
    ) async throws -> [ReviewItem] {
        var items: [ReviewItem] = []
        var paths = Set<String>()
        for requested in scope.roots {
            try Task.checkCancellation()
            let root = try await access.acquire(requested)
            defer { root.stopAccessingSecurityScopedResource() }
            try ReviewSafety.validateDestination(root)
            guard
                let entries = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else {
                throw CleanupError.message(
                    String(localized: "Cannot read \(root.lastPathComponent). Choose the folder again."))
            }
            while let url = entries.nextObject() as? URL {
                try Task.checkCancellation()
                guard ReviewSafety.isAllowed(url),
                    try url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true
                else {
                    entries.skipDescendants()
                    continue
                }
                guard paths.insert(url.standardizedFileURL.path).inserted else { continue }
                if var item = try Self.record(url, root: root) {
                    if let chatFolder = scope.exportedChatFolder, ReviewSafety.contains(url, in: chatFolder) {
                        item.facts.isExportedChatMedia = true
                    }
                    items.append(item)
                }
                if paths.count.isMultiple(of: 100) {
                    await progress(
                        CleanupProgress(String(localized: "Reading files"), completed: paths.count, total: 0))
                    await Task.yield()
                }
            }
        }
        return items
    }

    public static func mediaKind(_ url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .archive) || ["dmg", "iso", "gz", "7z", "rar"].contains(url.pathExtension) {
            return .archive
        }
        if type.conforms(to: .text) || type.conforms(to: .content) { return .document }
        return nil
    }

    public static func record(_ url: URL, root: URL) throws -> ReviewItem? {
        let identity = try ReviewSafety.identity(at: url)
        let values = try url.resourceValues(forKeys: [
            .isSymbolicLinkKey, .isAliasFileKey, .isDirectoryKey, .isPackageKey,
            .isHiddenKey, .creationDateKey, .volumeUUIDStringKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])
        guard values.isHidden != true else { return nil }
        let isLink = values.isSymbolicLink == true || values.isAliasFile == true
        if values.isDirectory == true && values.isPackage != true && !isLink { return nil }
        guard let kind = isLink ? MediaKind.other : mediaKind(url) else { return nil }
        let volume = values.volumeUUIDString ?? String(identity.deviceIdentifier ?? 0)
        var item = ReviewItem(
            id: "file:\(volume):\(identity.inodeIdentifier ?? 0)", source: .file(url),
            name: url.lastPathComponent, kind: kind, bytes: identity.sizeBytes ?? 0)
        item.root = root
        item.identity = identity
        item.createdAt = values.creationDate
        item.modifiedAt = identity.modifiedAt
        item.isLink = isLink
        item.isPackage = values.isPackage == true
        // lstat detects dataless File Provider items without reading their contents.
        var info = stat()
        _ = lstat(url.path, &info)
        item.isDownloaded =
            (info.st_flags & UInt32(SF_DATALESS)) == 0
            && !(values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded)
        if info.st_nlink > 1 && !item.isPackage { item.id += "|" + url.path }
        if item.isPackage && !item.isLink && item.isDownloaded {
            let summary = try ReviewSafety.packageSummary(url)
            item.bytes = summary.bytes
            item.packageVersion = summary.version
            item.isDownloaded = summary.downloaded
        }
        item.isCloudSynced = PathSafetyPolicy().cloudProvider(for: url) != nil
        if values.isSymbolicLink == true {
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            item.linkTarget =
                URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
        } else if values.isAliasFile == true {
            item.linkTarget = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting])
        }
        return item
    }
}
