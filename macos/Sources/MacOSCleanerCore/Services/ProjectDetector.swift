import Foundation

public actor ProjectDetector {
    /// Lowercased by contract — looked up by `fileName.lowercased()`.
    private let manifestTypes: [String: String] = [
        "package.json": "Node",
        "pnpm-lock.yaml": "Node",
        "yarn.lock": "Node",
        "bun.lockb": "Node",
        "pyproject.toml": "Python",
        "requirements.txt": "Python",
        "poetry.lock": "Python",
        "uv.lock": "Python",
        "cargo.toml": "Rust",
        "go.mod": "Go",
        "pom.xml": "Java",
        "build.gradle": "Java",
        "package.swift": "Swift",
        "dockerfile": "Docker",
        "docker-compose.yml": "Docker",
        "makefile": "Build",
        "gemfile": "Ruby",
        "podfile": "CocoaPods",
        "readme": "General",
        "readme.md": "General",
        ".git": "git-repository"
    ]

    private let generatedFolderNames: Set<String> = [
        "node_modules", "dist", "build", ".next", ".nuxt", ".turbo", ".parcel-cache",
        ".vite", "coverage", ".venv", "venv", ".tox", "__pycache__", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", "target", ".build", ".dart_tool", "DerivedData"
    ]

    private let sourceExtensions: Set<String>

    public init(policy: PathSafetyPolicy = PathSafetyPolicy()) {
        self.sourceExtensions = policy.sourceExtensions
    }

    public func detectProjects(in files: [FileRecord]) -> [ProjectUnit] {
        let manifests = files.filter { manifestTypes[$0.fileName.lowercased()] != nil || $0.fileExtension == "xcodeproj" || $0.fileExtension == "xcworkspace" }
        var grouped: [URL: [FileRecord]] = [:]

        for manifest in manifests {
            let root = manifest.url.deletingLastPathComponent()
            grouped[root.standardizedFileURL, default: []].append(manifest)
        }

        let sortedFiles = files.sorted { $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path }
        let sortedPaths = sortedFiles.map { $0.url.standardizedFileURL.path }

        return grouped.map { root, manifestRecords in
            let projectFiles = filesInPrefix(sortedFiles: sortedFiles, sortedPaths: sortedPaths, root: root)
            let generatedFiles = projectFiles.filter { record in
                record.url.pathComponents.contains(where: { generatedFolderNames.contains($0) })
            }
            let sourceFiles = projectFiles.filter { record in
                guard record.kind == .regularFile, let fileExtension = record.fileExtension else {
                    return false
                }
                return sourceExtensions.contains(fileExtension)
            }
            let lastActivity = projectFiles.compactMap(\.modifiedAt).max()
            let totalBytes = projectFiles.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
            let reclaimable = generatedFiles.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
            let type = dominantProjectType(for: manifestRecords)
            let inactiveCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            let status: ProjectStatus = (lastActivity ?? .distantPast) < inactiveCutoff ? .inactive : .active
            return ProjectUnit(
                id: root.path,
                name: root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent,
                rootURL: root,
                projectType: type,
                confidence: manifestRecords.count > 1 ? 0.92 : 0.78,
                lastActivityAt: lastActivity,
                manifestFiles: manifestRecords.map(\.url),
                sourceFilesCount: sourceFiles.count,
                generatedFilesCount: generatedFiles.count,
                totalBytes: totalBytes,
                reclaimableBytes: reclaimable,
                status: status
            )
        }
        .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Maximum manifest→file edges emitted per project. A monorepo root can
    /// contain hundreds of thousands of files; persisting a cartesian
    /// manifest×files edge set would explode the relationship_edges table.
    /// The Inspector builds on-demand edges for the focused file instead.
    public static let maxEdgesPerProject = 200

    public func buildEdges(files: [FileRecord], projects: [ProjectUnit]) -> [RelationshipEdge] {
        let sortedFiles = files.sorted { $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path }
        let sortedPaths = sortedFiles.map { $0.url.standardizedFileURL.path }
        var edges: [RelationshipEdge] = []
        for project in projects {
            let projectFiles = filesInPrefix(sortedFiles: sortedFiles, sortedPaths: sortedPaths, root: project.rootURL)
            let manifestIDs = projectFiles
                .filter { project.manifestFiles.contains($0.url) }
                .map(\.id)
            for manifestID in manifestIDs {
                var emitted = 0
                for file in projectFiles where file.id != manifestID {
                    guard emitted < Self.maxEdgesPerProject else { break }
                    edges.append(RelationshipEdge(
                        id: "\(manifestID)-\(file.id)-manifest",
                        fromFileID: manifestID,
                        toFileID: file.id,
                        edgeType: .sameProject,
                        confidence: project.confidence,
                        evidence: "File is inside detected project root \(project.rootURL.path)."
                    ))
                    emitted += 1
                }
            }
        }
        return edges
    }

    private func filesInPrefix(sortedFiles: [FileRecord], sortedPaths: [String], root: URL) -> [FileRecord] {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath + "/"
        let start = SortedPathSearch.lowerBound(sortedPaths, prefix)
        let end = SortedPathSearch.upperBound(sortedPaths, prefix)
        var result: [FileRecord] = []
        if start < sortedPaths.count, sortedPaths[start] == rootPath {
            result.append(sortedFiles[start])
            for i in (start + 1)..<end {
                result.append(sortedFiles[i])
            }
        } else {
            for i in start..<end {
                result.append(sortedFiles[i])
            }
        }
        return result
    }

    private func dominantProjectType(for manifests: [FileRecord]) -> String {
        let weighted = manifests.compactMap { record -> String? in
            if record.fileExtension == "xcodeproj" || record.fileExtension == "xcworkspace" {
                return "Xcode"
            }
            return manifestTypes[record.fileName.lowercased()]
        }
        if weighted.contains("Node") {
            return "Node"
        }
        if weighted.contains("Python") {
            return "Python"
        }
        return weighted.first ?? "General"
    }

}
