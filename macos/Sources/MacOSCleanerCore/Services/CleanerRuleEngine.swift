import Foundation
import os

public actor CleanerRuleEngine {
    private let policy: PathSafetyPolicy
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "CleanerRuleEngine")

    private static let lowRiskDeveloperArtifacts: Set<String> = [
        "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".next", ".nuxt",
        ".turbo", ".parcel-cache", ".vite", "coverage", ".dart_tool"
    ]

    /// Build-output directories that only make sense inside a detected project
    /// root (a directory containing a manifest such as package.json, Package.swift
    /// or *.xcodeproj). Matching these outside a project would risk deleting
    /// unrelated folders named "build", "dist" or "target" in a user's home or
    /// Documents folder, so a project root is required.
    private static let projectBoundBuildOutputs: Set<String> = [
        "node_modules", ".venv", "venv", ".tox", "dist", "build", "target", ".build", ".gradle"
    ]

    /// Xcode's global build cache (~/Library/Developer/Xcode/DerivedData). It
    /// lives outside project roots by definition, so the project-containment
    /// guard does not apply. CoreSimulator is not a cache: it holds devices.
    private static let globalBuildCacheDirectories: Set<String> = ["deriveddata"]

    private static let mediumRiskDeveloperArtifacts: Set<String> = projectBoundBuildOutputs.union(globalBuildCacheDirectories)

    public init(policy: PathSafetyPolicy = PathSafetyPolicy()) {
        self.policy = policy
    }

    /// True when the policy permits `record` as a cleanup candidate.
    private func isAllowed(_ record: FileRecord) -> Bool {
        if case .allow = policy.decide(target: record.url, isDirectory: record.kind == .directory) {
            return true
        }
        return false
    }

    public func analyze(files: [FileRecord], projects: [ProjectUnit], sessionID: String, posture: CleanupPosture = .conservative) -> ([Finding], [Recommendation]) {
        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        let directorySizes = subtreeSizes(for: files)

        // One autorelease pool per record: the policy and path checks autorelease URL
        // objects, and a pass over a million records otherwise keeps them all alive.
        for record in files {
            if let result = autoreleasepool(invoking: {
                firstFinding(for: record, sessionID: sessionID, directorySizes: directorySizes, projects: projects)
            }) {
                findings.append(result.finding)
                recommendations.append(result.recommendation)
            }
        }

        // One policy pass for the rules below. Each isAllowed call autoreleases
        // URLs, so the pool keeps a 1M-record pass from holding them all.
        let allowedFiles = files.filter { record in autoreleasepool { isAllowed(record) } }
        let screenshots = screenshotFindings(in: allowedFiles, sessionID: sessionID)
        findings.append(contentsOf: screenshots)
        for screenshot in screenshots {
            let recommendation = Recommendation(
                id: UUID().uuidString,
                findingID: screenshot.id,
                actionType: .moveToTrash,
                targetFileIDs: screenshot.targetFileIDs,
                confidence: screenshot.confidence,
                risk: screenshot.severity,
                reason: String(localized: "Review screenshots and screen recordings before moving them to Trash.", comment: "Recommendation reason for screenshot cleanup"),
                expectedBytesReclaimed: screenshot.bytesReclaimable,
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "screenshot_rule"
            )
            recommendations.append(recommendation)
        }

        let packageCacheResults = packageManagerCacheFindings(files: allowedFiles, sessionID: sessionID, directorySizes: directorySizes)
        findings.append(contentsOf: packageCacheResults.map(\.finding))
        recommendations.append(contentsOf: packageCacheResults.map(\.recommendation))

        let largeFiles = largeFileFindings(files: allowedFiles, sessionID: sessionID)
        findings.append(contentsOf: largeFiles.map(\.finding))
        recommendations.append(contentsOf: largeFiles.map(\.recommendation))
        let appLeftovers = appLeftoverFindings(files: allowedFiles, sessionID: sessionID, directorySizes: directorySizes)
        findings.append(contentsOf: appLeftovers.map(\.finding))
        recommendations.append(contentsOf: appLeftovers.map(\.recommendation))
        return (dedupeFindings(findings), dedupeRecommendations(recommendations))
    }

    private func developerArtifactFinding(
        _ record: FileRecord,
        sessionID: String,
        directorySizes: [String: Int64],
        projects: [ProjectUnit]
    ) -> (finding: Finding, recommendation: Recommendation)? {
        guard record.kind == .directory else {
            return nil
        }
        // Case-insensitive matching: macOS filesystems are case-insensitive by
        // default, so "Node_Modules" and "node_modules" refer to the same folder.
        let loweredName = record.fileName.lowercased()
        guard Self.lowRiskDeveloperArtifacts.contains(loweredName) || Self.mediumRiskDeveloperArtifacts.contains(loweredName) else {
            return nil
        }
        let size = directorySizes[record.displayPath] ?? record.sizeBytes
        guard size > 0 else {
            return nil
        }
        let project = projects.first { record.displayPath.hasPrefix($0.rootURL.path + "/") }
        // Build outputs (node_modules, dist, build, target, ...) are only proposed
        // when they sit inside a detected project root. Outside a project their
        // names are ambiguous, and deleting them could remove unrelated folders.
        if Self.projectBoundBuildOutputs.contains(loweredName) && project == nil {
            return nil
        }
        let isLowRisk = Self.lowRiskDeveloperArtifacts.contains(loweredName)
        let risk: RiskLevel = isLowRisk ? .low : .medium
        let confidence = project == nil && loweredName == "node_modules" ? 0.66 : (isLowRisk ? 0.94 : 0.84)
        let findingID = UUID().uuidString
        let evidence = [
            "folder_name": record.fileName,
            "project": project?.name ?? "unknown",
            "project_status": project?.status.rawValue ?? "unknown",
            "bytes": String(size)
        ]
        let finding = Finding(
            id: findingID,
            scanSessionID: sessionID,
            category: .developerArtifact,
            severity: risk,
            confidence: confidence,
            bytesReclaimable: size,
            summary: String(localized: "\(record.fileName) appears to be a rebuildable developer artifact.", comment: "Finding summary for developer artifact"),
            evidence: evidence,
            targetFileIDs: [record.id]
        )
        let recommendation = Recommendation(
            id: UUID().uuidString,
            findingID: findingID,
            actionType: .moveToTrash,
            targetFileIDs: [record.id],
            confidence: confidence,
            risk: risk,
            reason: reasonForDeveloperArtifact(record: record, project: project, risk: risk),
            expectedBytesReclaimed: size,
            requiresConfirmation: true,
            llmTraceID: nil,
            policyTraceID: "developer_artifact_rule"
        )
        return (finding, recommendation)
    }

    private func xcarchiveFinding(
        _ record: FileRecord,
        sessionID: String,
        directorySizes: [String: Int64]
    ) -> (finding: Finding, recommendation: Recommendation)? {
        guard record.kind == .directory, record.fileExtension == "xcarchive" else { return nil }
        let size = directorySizes[record.displayPath] ?? record.sizeBytes
        guard size > 0 else { return nil }
        let findingID = UUID().uuidString
        let finding = Finding(
            id: findingID,
            scanSessionID: sessionID,
            category: .developerArtifact,
            severity: .medium,
            confidence: 0.88,
            bytesReclaimable: size,
            summary: String(localized: "Xcode archive (.xcarchive) found.", comment: "Finding summary for xcarchive"),
            evidence: ["path": record.displayPath, "bytes": String(size)],
            targetFileIDs: [record.id]
        )
        let recommendation = Recommendation(
            id: UUID().uuidString,
            findingID: findingID,
            actionType: .inspectOnly,
            targetFileIDs: [record.id],
            confidence: 0.88,
            risk: .high,
            reason: String(localized: "Xcode archives keep the debug symbols for builds you shipped. They cannot be rebuilt from source. Delete them in Xcode Organizer only when you no longer need to read crash reports.", comment: "Recommendation reason for xcarchive review"),
            expectedBytesReclaimed: size,
            requiresConfirmation: true,
            llmTraceID: nil,
            policyTraceID: "xcarchive_rule"
        )
        return (finding, recommendation)
    }

    private func cacheOrLogFinding(
        _ record: FileRecord,
        sessionID: String,
        directorySizes: [String: Int64],
        projects: [ProjectUnit]
    ) -> (finding: Finding, recommendation: Recommendation)? {
        let components = record.url.pathComponents
        // Case-insensitive cache detection to catch "cache", "Cache", "CACHE" variants
        let isCache = components.contains(where: { $0.lowercased() == "caches" || $0.lowercased() == ".cache" || $0.lowercased() == "cache" })
        let isLog = components.contains(where: { $0.lowercased() == "logs" }) || record.fileExtension == "log"
        guard isCache || isLog else {
            return nil
        }
        // "node_modules/.cache"-style matches are only proposed inside a detected
        // project root; a stray node_modules outside any project is ambiguous.
        if components.contains(where: { $0.lowercased() == "node_modules" })
            && !projects.contains(where: { record.displayPath.hasPrefix($0.rootURL.path + "/") }) {
            return nil
        }
        let size = record.kind == .directory ? (directorySizes[record.displayPath] ?? record.sizeBytes) : record.sizeBytes
        guard size > 1024 * 1024 else {
            return nil
        }
        let category: FindingCategory = isLog ? .log : .cache
        let findingID = UUID().uuidString
        let finding = Finding(
            id: findingID,
            scanSessionID: sessionID,
            category: category,
            severity: .low,
            confidence: 0.9,
            bytesReclaimable: size,
            summary: isLog ? String(localized: "Old or large log file/folder.", comment: "Finding summary for log file") : String(localized: "Application or package cache.", comment: "Finding summary for cache"),
            evidence: ["path": record.displayPath, "bytes": String(size)],
            targetFileIDs: [record.id]
        )
        let recommendation = Recommendation(
            id: UUID().uuidString,
            findingID: findingID,
            actionType: .moveToTrash,
            targetFileIDs: [record.id],
            confidence: 0.9,
            risk: .low,
            reason: String(localized: "Caches and logs are usually rebuildable, but the action still requires review and uses Trash.", comment: "Recommendation reason for cache/log cleanup"),
            expectedBytesReclaimed: size,
            requiresConfirmation: true,
            llmTraceID: nil,
            policyTraceID: "cache_log_rule"
        )
        return (finding, recommendation)
    }

    /// Installer archive extensions. Internal so the natural-language planner
    /// can apply the same set to "old installers" commands.
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
    private static let desktopAndDocuments = ["Desktop", "Documents"].map {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).standardizedFileURL.path + "/"
    }

    private func oldDownloadFinding(_ record: FileRecord, sessionID: String) -> (finding: Finding, recommendation: Recommendation)? {
        let folders = Set(record.url.pathComponents.map { $0.lowercased() })
        let isInstaller = record.fileExtension.map(Self.installerExtensions.contains) ?? false
        let inDownloads = folders.contains("downloads")
        // Archives count in Downloads only; installers also in ~/Desktop and ~/Documents.
        let path = record.url.standardizedFileURL.path
        guard record.kind == .regularFile || (record.kind == .package && isInstaller),
              inDownloads || (isInstaller && Self.desktopAndDocuments.contains { path.hasPrefix($0) }),
              let modifiedAt = record.modifiedAt,
              let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()),
              modifiedAt < cutoff else {
            return nil
        }
        let oldDownloadExtensions = Self.installerExtensions.union(["zip", "tar", "gz", "xz", "rar", "7z", "img", "deb", "rpm", "msi"])
        guard let fileExtension = record.fileExtension, oldDownloadExtensions.contains(fileExtension) else {
            return nil
        }
        // People keep some installers on purpose: outside Downloads, bulk approval skips them.
        let risk: RiskLevel = isInstaller && inDownloads ? .low : .medium
        let findingID = UUID().uuidString
        let finding = Finding(
            id: findingID,
            scanSessionID: sessionID,
            category: isInstaller ? .oldInstaller : .oldDownload,
            severity: risk,
            confidence: 0.86,
            bytesReclaimable: record.sizeBytes,
            summary: String(localized: "Old download archive or installer.", comment: "Finding summary for old download"),
            evidence: ["modified_at": modifiedAt.ISO8601Format(), "extension": fileExtension],
            targetFileIDs: [record.id]
        )
        let recommendation = Recommendation(
            id: UUID().uuidString,
            findingID: findingID,
            actionType: .moveToTrash,
            targetFileIDs: [record.id],
            confidence: 0.86,
            risk: risk,
            reason: String(localized: "The file is an old downloaded archive or installer. Review before moving it to Trash.", comment: "Recommendation reason for old download cleanup"),
            expectedBytesReclaimed: record.sizeBytes,
            requiresConfirmation: true,
            llmTraceID: nil,
            policyTraceID: "old_download_rule"
        )
        return (finding, recommendation)
    }

    private func codingAgentFinding(
        _ record: FileRecord,
        sessionID: String,
        directorySizes: [String: Int64]
    ) -> (finding: Finding, recommendation: Recommendation)? {
        let components = record.url.pathComponents
        let agentRoots: Set<String> = [".claude", ".codex", ".opencode", ".factory", ".openclaw", ".hermes", ".cursor", ".vscode"]
        guard components.contains(where: { agentRoots.contains($0) }) else {
            return nil
        }
        let safeNames: Set<String> = ["logs", "log", "cache", "caches", "tmp", "temp", "outputs"]
        guard components.contains(where: { safeNames.contains($0.lowercased()) }) else {
            return nil
        }
        let size = record.kind == .directory ? (directorySizes[record.displayPath] ?? record.sizeBytes) : record.sizeBytes
        guard size > 0 else {
            return nil
        }
        let findingID = UUID().uuidString
        let finding = Finding(
            id: findingID,
            scanSessionID: sessionID,
            category: .codingAgentArtifact,
            severity: .medium,
            confidence: 0.74,
            bytesReclaimable: size,
            summary: String(localized: "Coding-agent log/cache artifact. Config and memory paths remain protected.", comment: "Finding summary for coding agent artifact"),
            evidence: ["path": record.displayPath, "bytes": String(size)],
            targetFileIDs: [record.id]
        )
        let recommendation = Recommendation(
            id: UUID().uuidString,
            findingID: findingID,
            actionType: .archive,
            targetFileIDs: [record.id],
            confidence: 0.74,
            risk: .medium,
            reason: String(localized: "This looks like a coding-agent log/cache path. Archive is suggested before deletion because agent sessions can contain useful private context.", comment: "Recommendation reason for coding agent artifact"),
            expectedBytesReclaimed: size,
            requiresConfirmation: true,
            llmTraceID: nil,
            policyTraceID: "coding_agent_safe_candidate_rule"
        )
        return (finding, recommendation)
    }

    private func organizationFinding(_ record: FileRecord, sessionID: String) -> (finding: Finding, recommendation: Recommendation)? {
        guard record.kind == .regularFile,
              record.url.pathComponents.contains(where: { $0.lowercased() == "downloads" }),
              let modifiedAt = record.modifiedAt,
              let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: Date()),
              modifiedAt < cutoff else {
            return nil
        }
        let organizeExtensions: Set<String> = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "png", "jpg", "jpeg", "mov", "mp4"]
        guard let fileExtension = record.fileExtension, organizeExtensions.contains(fileExtension) else {
            return nil
        }
        let findingID = UUID().uuidString
        let finding = Finding(
            id: findingID,
            scanSessionID: sessionID,
            category: .organization,
            severity: .medium,
            confidence: 0.68,
            bytesReclaimable: 0,
            summary: String(localized: "Downloaded file may belong in an archive or tagged collection.", comment: "Finding summary for organization candidate"),
            evidence: ["extension": fileExtension, "modified_at": modifiedAt.ISO8601Format()],
            targetFileIDs: [record.id]
        )
        let recommendation = Recommendation(
            id: UUID().uuidString,
            findingID: findingID,
            actionType: .tag,
            targetFileIDs: [record.id],
            confidence: 0.68,
            risk: .medium,
            reason: String(localized: "Tag this older download for review instead of moving it automatically.", comment: "Recommendation reason for organization tagging"),
            expectedBytesReclaimed: 0,
            requiresConfirmation: true,
            llmTraceID: nil,
            policyTraceID: "downloads_organization_rule"
        )
        return (finding, recommendation)
    }

    private func largeFileFindings(files: [FileRecord], sessionID: String) -> [(finding: Finding, recommendation: Recommendation)] {
        files
            .filter { $0.kind == .regularFile && $0.sizeBytes >= FileCrawler.largeFileBytes }
            .map { record in
                let findingID = UUID().uuidString
                let finding = Finding(
                    id: findingID,
                    scanSessionID: sessionID,
                    category: .largeFile,
                    severity: .high,
                    confidence: 0.7,
                    bytesReclaimable: record.sizeBytes,
                    summary: String(localized: "Large file worth reviewing.", comment: "Finding summary for large file"),
                    evidence: ["path": record.displayPath, "bytes": String(record.sizeBytes)],
                    targetFileIDs: [record.id]
                )
                let recommendation = Recommendation(
                    id: UUID().uuidString,
                    findingID: findingID,
                    actionType: .inspectOnly,
                    targetFileIDs: [record.id],
                    confidence: 0.7,
                    risk: .high,
                    reason: String(localized: "This file is over 1 GB. Review whether it can be moved or deleted.", comment: "Recommendation reason for large file"),
                    expectedBytesReclaimed: record.sizeBytes,
                    requiresConfirmation: true,
                    llmTraceID: nil,
                    policyTraceID: "large_file_rule"
                )
                return (finding, recommendation)
            }
    }

    private func appLeftoverFindings(
        files: [FileRecord],
        sessionID: String,
        directorySizes: [String: Int64]
    ) -> [(finding: Finding, recommendation: Recommendation)] {
        let installedApps = installedApplicationNames()
        // Only flag DIRECT children of "Application Support" — nested subdirectories
        // (e.g. AppName/Caches, AppName/Data) would cause false positives if flagged
        // individually because their names won't match any installed app.
        let supportDirectories = files.filter { record in
            record.kind == .directory
                && record.url.deletingLastPathComponent().lastPathComponent == "Application Support"
                && isAllowed(record)
        }
        return supportDirectories.compactMap { record in
            let normalizedName = normalizeAppName(record.fileName)
            guard !installedApps.contains(normalizedName) else {
                return nil
            }
            let size = directorySizes[record.displayPath] ?? record.sizeBytes
            guard size > 50_000_000 else {
                return nil
            }
            let findingID = UUID().uuidString
            let finding = Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: .appLeftover,
                severity: .medium,
                confidence: 0.62,
                bytesReclaimable: size,
                summary: String(localized: "Possible app support leftover for an app that is not currently installed.", comment: "Finding summary for app leftover"),
                evidence: ["folder": record.displayPath, "bytes": String(size)],
                targetFileIDs: [record.id]
            )
            let recommendation = Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .moveToTrash,
                targetFileIDs: [record.id],
                confidence: 0.62,
                risk: .medium,
                reason: String(localized: "This Application Support folder does not clearly match an installed app. Review carefully before moving it to Trash.", comment: "Recommendation reason for app leftover"),
                expectedBytesReclaimed: size,
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "app_leftover_rule"
            )
            return (finding, recommendation)
        }
    }

    private func reasonForDeveloperArtifact(record: FileRecord, project: ProjectUnit?, risk: RiskLevel) -> String {
        if let project {
            return String(localized: "The folder is a rebuildable artifact inside the \(project.name) project. The project is \(project.status.rawValue), and source/config files remain protected.", comment: "Recommendation reason for developer artifact with project")
        }
        if risk == .low {
            return String(localized: "The folder is a low-risk rebuildable cache or test artifact. It will still go through review and Trash.", comment: "Recommendation reason for low-risk developer artifact")
        }
        return String(localized: "The folder is a rebuildable developer artifact, but the surrounding project is unclear, so it requires grouped review.", comment: "Recommendation reason for developer artifact without project")
    }

    /// The first rule that matches the record, in priority order.
    private func firstFinding(
        for record: FileRecord, sessionID: String, directorySizes: [String: Int64], projects: [ProjectUnit]
    ) -> (finding: Finding, recommendation: Recommendation)? {
        guard isAllowed(record) else { return nil }
        return developerArtifactFinding(record, sessionID: sessionID, directorySizes: directorySizes, projects: projects)
            ?? xcarchiveFinding(record, sessionID: sessionID, directorySizes: directorySizes)
            ?? cacheOrLogFinding(record, sessionID: sessionID, directorySizes: directorySizes, projects: projects)
            ?? oldDownloadFinding(record, sessionID: sessionID)
            ?? codingAgentFinding(record, sessionID: sessionID, directorySizes: directorySizes)
            ?? organizationFinding(record, sessionID: sessionID)
    }

    private func subtreeSizes(for files: [FileRecord]) -> [String: Int64] {
        let directories = files.filter { $0.kind == .directory || $0.kind == .package }
        // Include all file kinds with sizeBytes (not just regularFile) to avoid undercounting
        // directories that contain symlinks, packages, or other non-regular files. A
        // summarized folder is a leaf: its size is already the total of its contents.
        let sortedFiles = files.filter { ($0.rolledUpItemCount != nil || ![.directory, .package].contains($0.kind)) && $0.sizeBytes > 0 }
            .sorted { $0.displayPath < $1.displayPath }
        let sortedPaths = sortedFiles.map(\.displayPath)
        var sizes: [String: Int64] = [:]
        for directory in directories {
            let prefix = directory.displayPath + "/"
            let start = SortedPathSearch.lowerBound(sortedPaths, prefix)
            let end = SortedPathSearch.upperBound(sortedPaths, prefix)
            var total: Int64 = directory.rolledUpItemCount != nil ? directory.sizeBytes : 0
            for i in start..<end {
                total += sortedFiles[i].sizeBytes
            }
            sizes[directory.displayPath] = total
        }
        return sizes
    }



    private func installedApplicationNames() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications", isDirectory: true),
            // Homebrew Caskroom — apps installed via `brew install --cask`
            home.appendingPathComponent("Applications/Caskroom", isDirectory: true),
        ]
        let names = roots.flatMap { root -> [String] in
            guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                return []
            }
            return urls.filter { $0.pathExtension == "app" }.map { normalizeAppName($0.deletingPathExtension().lastPathComponent) }
        }
        return Set(names)
    }

    private func normalizeAppName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    func screenshotFindings(in files: [FileRecord], sessionID: String) -> [Finding] {
        let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "heic", "mov", "mp4"]
        let screenshotFiles = files.filter { file in
            guard let ext = file.fileExtension?.lowercased(), screenshotExtensions.contains(ext) else { return false }
            let name = file.fileName.lowercased()
            return name.hasPrefix("screen shot ") || name.hasPrefix("screenshot ") || name.hasPrefix("screen recording ")
        }
        guard !screenshotFiles.isEmpty else { return [] }
        // Group by parent directory for granular approve/reject control
        let grouped = Dictionary(grouping: screenshotFiles) { $0.url.deletingLastPathComponent().lastPathComponent }
        return grouped.compactMap { (folderName, groupFiles) in
            let totalBytes = groupFiles.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
            guard !groupFiles.isEmpty else { return nil }
            return Finding(
                id: UUID().uuidString,
                scanSessionID: sessionID,
                category: .screenshot,
                severity: .low,
                confidence: 0.85,
                bytesReclaimable: totalBytes,
                summary: groupFiles.count == 1
                    ? String(localized: "1 screenshot in \(folderName) (\(totalBytes.formattedByteCount))", comment: "Screenshot finding summary per folder, singular")
                    : String(localized: "\(groupFiles.count) screenshots in \(folderName) (\(totalBytes.formattedByteCount))", comment: "Screenshot finding summary per folder"),
                evidence: ["type": "screenshot", "folder": folderName, "count": "\(groupFiles.count)"],
                targetFileIDs: groupFiles.map(\.id)
            )
        }
    }

    private func packageManagerCacheFindings(files: [FileRecord], sessionID: String, directorySizes: [String: Int64]) -> [(finding: Finding, recommendation: Recommendation)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cachePaths: [(path: String, name: String)] = [
            (home.appendingPathComponent(".npm").path, ".npm"),
            (home.appendingPathComponent(".cache/pip").path, "pip cache"),
        ]
        return files.compactMap { record in
            guard record.kind == .directory else { return nil }
            guard let match = cachePaths.first(where: { record.displayPath == $0.0 }) else {
                return nil
            }
            // Directories report only their own allocation size from the crawler;
            // use the computed subtree total so the planner sizes the action correctly.
            let size = directorySizes[record.displayPath] ?? record.sizeBytes
            guard size > 0 else { return nil }
            let findingID = UUID().uuidString
            let finding = Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: .packageManagerCleanup,
                severity: .low,
                confidence: 0.91,
                bytesReclaimable: size,
                summary: String(localized: "\(match.name) cache directory.", comment: "Finding summary for package manager cache"),
                evidence: ["path": record.displayPath, "bytes": String(size)],
                targetFileIDs: [record.id]
            )
            let recommendation = Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .moveToTrash,
                targetFileIDs: [record.id],
                confidence: 0.91,
                risk: .low,
                reason: String(localized: "Package manager caches are rebuildable. Review before moving to Trash.", comment: "Recommendation reason for package manager cache"),
                expectedBytesReclaimed: size,
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "package_manager_cache_rule"
            )
            return (finding, recommendation)
        }
    }

    private func dedupeFindings(_ findings: [Finding]) -> [Finding] {
        var bestByKey: [String: Finding] = [:]
        for finding in findings {
            let key = "\(finding.category.rawValue)-\(finding.targetFileIDs.joined(separator: ","))"
            if let existing = bestByKey[key] {
                if finding.confidence > existing.confidence {
                    bestByKey[key] = finding
                }
            } else {
                bestByKey[key] = finding
            }
        }
        return Array(bestByKey.values)
    }

    private func dedupeRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
        var bestByKey: [String: Recommendation] = [:]
        for recommendation in recommendations {
            let key = "\(recommendation.actionType.rawValue)-\(recommendation.targetFileIDs.joined(separator: ","))"
            if let existing = bestByKey[key] {
                if recommendation.confidence > existing.confidence {
                    bestByKey[key] = recommendation
                }
            } else {
                bestByKey[key] = recommendation
            }
        }
        return Array(bestByKey.values)
    }
}
