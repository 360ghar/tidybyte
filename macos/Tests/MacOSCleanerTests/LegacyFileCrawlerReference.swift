// swiftlint:disable function_body_length line_length
// Verbatim copy of the pre-rewrite crawler: a parity and benchmark fixture, not product code.
import Foundation
import os
@testable import MacOSCleanerCore

/// The crawler before the lstat rewrite, kept only to prove parity and measure speed.

actor LegacyFileCrawlerReference {
    private let fileManager: FileManager
    private let policy: PathSafetyPolicy
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "FileCrawler")

    init(fileManager: FileManager = .default, policy: PathSafetyPolicy = PathSafetyPolicy()) {
        self.fileManager = fileManager
        self.policy = policy
    }

    func crawl(rootURLs: [URL], sessionID: String) async -> ([FileRecord], Int) {
        var records: [FileRecord] = []
        var errors = 0

        await withTaskGroup(of: ([FileRecord], Int).self) { group in
            for root in rootURLs {
                group.addTask {
                    await self.crawlRoot(root, sessionID: sessionID)
                }
            }
            for await result in group {
                records.append(contentsOf: result.0)
                errors += result.1
            }
        }

        return (records.sorted { $0.displayPath < $1.displayPath }, errors)
    }

    private func crawlRoot(_ root: URL, sessionID: String) async -> ([FileRecord], Int) {
        // A protected root (.ssh, SIP path, Trash) is never crawled at all —
        // the per-child checks below only guard descendants.
        if policy.shouldSkipTraversal(of: root) {
            logger.warning("Skipping protected scan root: \(root.path, privacy: .public)")
            return ([], 0)
        }
        // isReadableFile returns false for directories (only checks regular files).
        // For directory roots, verify existence and let the enumerator catch access errors.
        let rootIsFile = fileManager.isReadableFile(atPath: root.path)
        var isDir: ObjCBool = false
        let rootIsDir = fileManager.fileExists(atPath: root.path, isDirectory: &isDir) && isDir.boolValue
        guard rootIsFile || rootIsDir else {
            logger.error("Unreadable scan root: \(root.path, privacy: .public)")
            return ([], 1)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .localizedTypeDescriptionKey,
            .tagNamesKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .fileResourceIdentifierKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                self.logger.warning("Crawler skipped \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            }
        ) else {
            return ([], 1)
        }

        var output: [FileRecord] = []
        var errors = 0
        var visitedInodes = Set<String>()

        if let rootRecord = makeRecord(for: root, sessionID: sessionID) {
            output.append(rootRecord)
            if let device = rootRecord.identity.deviceIdentifier,
               let inode = rootRecord.identity.inodeIdentifier {
                visitedInodes.insert("\(device)-\(inode)")
            }
        }

        while let fileURL = enumerator.nextObject() as? URL {
            // Cooperative cancellation: stop enumerating promptly when the scan is cancelled.
            // Partial results are discarded by the orchestrator's cancellation check.
            if Task.isCancelled {
                break
            }
            if policy.shouldSkipTraversal(of: fileURL) {
                enumerator.skipDescendants()
            }
            guard let record = makeRecord(for: fileURL, sessionID: sessionID) else {
                errors += 1
                continue
            }
            // Hard links share an inode with an already-visited path. The record is
            // still emitted — dropping it silently under-counted files and subtree
            // bytes. NSDirectoryEnumerator never descends into symlinked directories,
            // so symlink cycles cannot occur; the inode set is purely informational.
            if let device = record.identity.deviceIdentifier,
               let inode = record.identity.inodeIdentifier {
                _ = visitedInodes.insert("\(device)-\(inode)")
            }
            output.append(record)
        }

        return (output, errors)
    }

    private func makeRecord(for url: URL, sessionID: String) -> FileRecord? {
        do {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isPackageKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
                .localizedTypeDescriptionKey,
                .tagNamesKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .fileResourceIdentifierKey
            ]
            let values = try url.resourceValues(forKeys: keys)
            let isDirectory = values.isDirectory ?? false
            let isSymlink = values.isSymbolicLink ?? false
            let isPackage = values.isPackage ?? false
            let kind: FileKind
            if isSymlink {
                kind = .symlink
            } else if isPackage {
                kind = .package
            } else if isDirectory {
                kind = .directory
            } else if values.isRegularFile ?? false {
                kind = .regularFile
            } else {
                kind = .other
            }

            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let owner = attributes?[.ownerAccountName] as? String
            let permissions = (attributes?[.posixPermissions] as? NSNumber).map { String($0.uint16Value, radix: 8) }
            let device = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
            let inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
            let sizeFromAttributes = (attributes?[.size] as? NSNumber)?.int64Value
            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            let resolvedSize = kind == .directory ? size : (sizeFromAttributes ?? size)
            let cloudProvider = policy.cloudProvider(for: url)
            let riskFlags = policy.riskFlags(for: url, isDirectory: isDirectory)
            let symlinkTarget: URL? = isSymlink ? {
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path != url.path else {
                    return nil as URL?
                }
                return URL(fileURLWithPath: resolved.path) as URL?
            }() : nil
            let source: FileSource
            if cloudProvider == "iCloud" {
                source = .iCloudLocal
            } else if cloudProvider == "Google Drive" {
                source = .googleDriveLocal
            } else if cloudProvider == "Dropbox" {
                source = .dropboxLocal
            } else if cloudProvider == "OneDrive" {
                source = .oneDriveLocal
            } else {
                source = .local
            }

            return FileRecord(
                id: StableFileID.forStandardizedPath(url.standardizedFileURL.path, sizeBytes: resolvedSize, modifiedAt: values.contentModificationDate),
                scanSessionID: sessionID,
                source: source,
                url: url.standardizedFileURL,
                displayPath: url.standardizedFileURL.path,
                fileName: url.lastPathComponent,
                fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased(),
                utiDescription: values.localizedTypeDescription,
                kind: kind,
                sizeBytes: resolvedSize,
                createdAt: values.creationDate,
                modifiedAt: values.contentModificationDate,
                lastOpenedAt: values.contentAccessDate,
                owner: owner,
                permissions: permissions,
                isSymlink: isSymlink,
                symlinkTarget: symlinkTarget,
                isPackage: isPackage,
                isCloudPlaceholder: values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current,
                cloudProvider: cloudProvider,
                finderTags: values.tagNames ?? [],
                spotlightMetadata: [:],
                riskFlags: riskFlags,
                identity: FileIdentity(
                    deviceIdentifier: device,
                    inodeIdentifier: inode,
                    resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                    sizeBytes: resolvedSize,
                    modifiedAt: values.contentModificationDate
                ),
                capabilities: [.canMove, .canTrash, .canRestore, .canTag]
            )
        } catch {
            logger.warning("Metadata unavailable for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
// swiftlint:enable function_body_length line_length
