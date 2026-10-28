import Foundation
import SwiftUI
import MacOSCleanerCore

/// Grouping dimension shared by the Explore visualizations.
enum ExploreGrouping: String, CaseIterable, Identifiable, Sendable {
    case byFolder
    case byType
    case byAge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byFolder:
            String(localized: "By Folder", comment: "Explore grouping option")
        case .byType:
            String(localized: "By Type", comment: "Explore grouping option")
        case .byAge:
            String(localized: "By Age", comment: "Explore grouping option")
        }
    }
}

/// One aggregated node rendered by the Explore visualizations.
/// Built from already-scanned `FileRecord` values; no new scanning logic.
struct ExploreGroup: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var bytes: Int64
    var fileCount: Int
    /// Tooltip subtitle, e.g. the full folder path.
    var detail: String?
    /// Stable color assignment: siblings cycle the chart palette,
    /// descendants inherit their top-level ancestor's index.
    var paletteIndex: Int
    /// True for By-folder groups: views resolve the color from
    /// `FolderPastel` by folder name instead of `paletteIndex`, so the same
    /// folder keeps its pastel across scans, views, and launches.
    var usesFolderPastel: Bool = false
    var children: [ExploreGroup]
}

/// A flattened slice of the folder tree for radial / icicle layouts.
/// Fractions are relative to the grand total (0..<1).
struct SunburstSector: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var bytes: Int64
    var fileCount: Int
    var depth: Int
    var startFraction: Double
    var endFraction: Double
    var paletteIndex: Int
    /// Mirrors `ExploreGroup.usesFolderPastel` so radial/icicle views keep
    /// folder pastels without re-deriving the grouping.
    var usesFolderPastel: Bool = false

    var sweepFraction: Double { max(0, endFraction - startFraction) }
}

/// Categorical chart palette cycled by `paletteIndex`. System colors adapt
/// to light, dark, and Increase Contrast on their own.
enum ExploreChartPalette {
    // CategoricalPalette wraps SwiftUI Color (non-Sendable); the ramp is
    // immutable after initialization, so unchecked shared access is safe.
    nonisolated(unsafe) private static let ramp: [CategoricalPalette] = [
        .blue, .teal, .green, .yellow, .orange, .coral, .pink, .purple,
    ]

    static func palette(for index: Int) -> CategoricalPalette {
        ramp[safeIfValid: abs(index) % ramp.count] ?? .blue
    }

    /// Palette for a group: By-folder groups resolve through `FolderPastel`
    /// by folder name (stable across scans/views/launches); everything else
    /// cycles the generic categorical ramp by `paletteIndex`. A nil group
    /// (e.g. a connector with no matching branch) falls back to sky.
    static func palette(for group: ExploreGroup?) -> CategoricalPalette {
        guard let group else {
            return .blue
        }
        guard group.usesFolderPastel else {
            return palette(for: group.paletteIndex)
        }
        return FolderPastel.palette(forFolderName: group.name)
    }

    /// Non-optional convenience over the optional overload.
    static func palette(for group: ExploreGroup) -> CategoricalPalette {
        palette(for: Optional(group))
    }

    /// Palette for a radial/flame sector: folder sectors resolve through
    /// `FolderPastel` by name; others cycle the generic ramp by index.
    static func palette(for sector: SunburstSector) -> CategoricalPalette {
        guard sector.usesFolderPastel else {
            return palette(for: sector.paletteIndex)
        }
        return FolderPastel.palette(forFolderName: sector.name)
    }
}

private extension Array {
    subscript(safeIfValid index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Stateless builder turning scanned files into visualization-ready groups.
/// Stateless `enum` namespace per the codebase's service conventions.
enum ExploreTreeBuilder {
    /// Files larger than this count as "big" for the Age Map spotlight.
    static let bigFileThresholdBytes: Int64 = 100_000_000
    /// Files untouched longer than this surface in the Age Map spotlight.
    static let untouchedThresholdDays = 180

    static func filteredFiles(_ files: [FileRecord], nameFilter: String) -> [FileRecord] {
        let trimmed = nameFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return files
        }
        return files.filter { $0.fileName.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Largest member of a group by scanned size. Used to Focus/Stage a
    /// concrete FileRecord from an aggregated group selection.
    static func largestMember(of group: ExploreGroup, in files: [FileRecord]) -> FileRecord? {
        members(of: group, in: files).max { $0.sizeBytes < $1.sizeBytes }
    }

    /// All scanned records belonging to a group: folder groups match by path
    /// prefix (their `id` is the folder path), type groups match by extension,
    /// age groups match by last-touched bucket.
    static func members(of group: ExploreGroup, in files: [FileRecord]) -> [FileRecord] {
        if group.id.hasPrefix("ext:") {
            let ext = String(group.id.dropFirst(4))
            if ext == String(localized: "No Extension", comment: "Explore extension key for files without one") {
                return files.filter { ($0.fileExtension ?? "").isEmpty }
            }
            let wanted = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
            return files.filter { ($0.fileExtension ?? "").lowercased() == wanted.lowercased() }
        }
        if group.id.hasPrefix("age:") {
            let bucket = String(group.id.dropFirst(4))
            return files.filter { ageBucketID(for: $0) == bucket }
        }
        if group.id == "__other__" {
            return []
        }
        let prefix = group.id.hasSuffix("/") ? group.id : group.id + "/"
        return files.filter { $0.url.path == group.id || $0.url.path.hasPrefix(prefix) }
    }

    /// Age-bucket id matching `buildAgeGroups` ("7d" | "30d" | "90d" | "1y" | "older" | "unknown").
    static func ageBucketID(for file: FileRecord) -> String {
        guard let touched = lastTouchedDate(for: file) else {
            return "unknown"
        }
        let days = Date().timeIntervalSince(touched) / 86_400
        if days <= 7 {
            return "7d"
        }
        if days <= 30 {
            return "30d"
        }
        if days <= 90 {
            return "90d"
        }
        if days <= 365 {
            return "1y"
        }
        return "older"
    }

    /// Top-level groups for the requested dimension.
    static func build(
        files: [FileRecord],
        grouping: ExploreGrouping,
        maxDepth: Int,
        maxChildren: Int = 12
    ) -> [ExploreGroup] {
        switch grouping {
        case .byFolder:
            buildFolderTree(files: files, maxDepth: max(1, maxDepth), maxChildren: maxChildren)
        case .byType:
            buildTypeGroups(files: files, maxChildren: maxChildren)
        case .byAge:
            buildAgeGroups(files: files)
        }
    }

    /// Flattened radial sectors (depth 1 = first ring) for sunburst / flame.
    static func sectors(
        groups: [ExploreGroup],
        maxDepth: Int,
        maxChildren: Int = 10
    ) -> [SunburstSector] {
        let total = groups.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
        guard total > 0 else {
            return []
        }
        var out: [SunburstSector] = []
        var cursor = 0.0
        for group in groups {
            let sweep = Double(max(0, group.bytes)) / Double(total)
            appendSectors(
                group: group,
                depth: 1,
                start: cursor,
                sweep: sweep,
                maxDepth: max(1, maxDepth),
                maxChildren: maxChildren,
                into: &out
            )
            cursor += sweep
        }
        return out
    }

    /// Sectors regrouped into one row per depth level, ordered left to right.
    static func flameRows(
        groups: [ExploreGroup],
        maxDepth: Int,
        maxChildren: Int = 10
    ) -> [[SunburstSector]] {
        let flat = sectors(groups: groups, maxDepth: maxDepth, maxChildren: maxChildren)
        let byDepth = Dictionary(grouping: flat, by: \.depth)
        return byDepth.keys.sorted().compactMap { depth in
            byDepth[depth]?.sorted { $0.startFraction < $1.startFraction }
        }
    }

    // MARK: - By Folder

    private final class FolderTrieNode {
        let name: String
        let path: String
        var bytes: Int64 = 0
        var fileCount: Int = 0
        var children: [String: FolderTrieNode] = [:]

        init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    private static func buildFolderTree(
        files: [FileRecord],
        maxDepth: Int,
        maxChildren: Int
    ) -> [ExploreGroup] {
        guard !files.isEmpty else {
            return []
        }
        let componentLists = files.map { $0.url.pathComponents }
        let commonLength = commonPrefixLength(of: componentLists)
        let commonPath = joinComponents(componentLists.first?.prefix(commonLength) ?? [])
        let rootName: String = {
            let last = URL(fileURLWithPath: commonPath).lastPathComponent
            return last.isEmpty ? commonPath : last
        }()
        let root = FolderTrieNode(name: rootName, path: commonPath)
        for file in files {
            let components = file.url.pathComponents
            let relative = Array(components.dropFirst(commonLength))
            // The last component is the file itself; intermediate components
            // are folders. Anything deeper than maxDepth rolls up.
            let folders = Array(relative.dropLast().prefix(maxDepth))
            root.bytes += max(0, file.sizeBytes)
            root.fileCount += 1
            var node = root
            var pathSoFar = commonPath
            for folder in folders {
                pathSoFar += "/" + folder
                if node.children[folder] == nil {
                    node.children[folder] = FolderTrieNode(name: folder, path: pathSoFar)
                }
                guard let next = node.children[folder] else {
                    break
                }
                next.bytes += max(0, file.sizeBytes)
                next.fileCount += 1
                node = next
            }
        }
        // Depth-1 children of the common root are the top-level groups.
        let top = root.children.values.sorted { $0.bytes > $1.bytes }
        return cappedGroups(from: top, maxChildren: maxChildren, paletteBase: 0)
    }

    private static func cappedGroups(
        from nodes: [FolderTrieNode],
        maxChildren: Int,
        paletteBase: Int
    ) -> [ExploreGroup] {
        let kept = Array(nodes.prefix(max(1, maxChildren)))
        var groups = kept.enumerated().map { index, node in
            convertNode(node, paletteIndex: paletteBase + index)
        }
        let remainder = nodes.dropFirst(kept.count)
        if !remainder.isEmpty {
            let bytes = remainder.reduce(Int64(0)) { $0 + $1.bytes }
            let count = remainder.reduce(0) { $0 + $1.fileCount }
            groups.append(ExploreGroup(
                id: "__other__",
                name: String(localized: "Other", comment: "Explore rollup group for small entries"),
                bytes: bytes,
                fileCount: count,
                detail: nil,
                paletteIndex: paletteBase + kept.count,
                children: []
            ))
        }
        return groups
    }

    private static func convertNode(_ node: FolderTrieNode, paletteIndex: Int) -> ExploreGroup {
        let kids = node.children.values.sorted { $0.bytes > $1.bytes }
        return ExploreGroup(
            id: node.path.isEmpty ? node.name : node.path,
            name: node.name,
            bytes: node.bytes,
            fileCount: node.fileCount,
            detail: node.path,
            paletteIndex: paletteIndex,
            usesFolderPastel: true,
            children: kids.map { convertNode($0, paletteIndex: paletteIndex) }
        )
    }

    private static func commonPrefixLength(of lists: [[String]]) -> Int {
        guard let first = lists.first else {
            return 0
        }
        var length = 0
        for component in first {
            let matchesAll = lists.allSatisfy { $0.count > length && $0[length] == component }
            guard matchesAll else {
                break
            }
            length += 1
        }
        return length
    }

    private static func joinComponents(_ components: ArraySlice<String>) -> String {
        let parts = Array(components)
        guard !parts.isEmpty else {
            return "/"
        }
        if parts == ["/"] {
            return "/"
        }
        var joined = parts.joined(separator: "/")
        if !joined.hasPrefix("/") {
            joined = "/" + joined
        }
        return joined
    }

    // MARK: - By Type

    private static func buildTypeGroups(files: [FileRecord], maxChildren: Int) -> [ExploreGroup] {
        let grouped = Dictionary(grouping: files) { file -> String in
            let ext = (file.fileExtension ?? "").lowercased()
            return ext.isEmpty
                ? String(localized: "No Extension", comment: "Explore group for files without an extension")
                : ".\(ext)"
        }
        let sorted = grouped.map { (key: $0.key, files: $0.value) }.sorted {
            $0.files.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
                > $1.files.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        }
        let kept = Array(sorted.prefix(max(1, maxChildren)))
        var groups = kept.enumerated().map { index, entry in
            ExploreGroup(
                id: "ext:\(entry.key)",
                name: entry.key,
                bytes: entry.files.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) },
                fileCount: entry.files.count,
                detail: nil,
                paletteIndex: index,
                children: []
            )
        }
        let remainder = sorted.dropFirst(kept.count)
        if !remainder.isEmpty {
            let rest = remainder.flatMap(\.files)
            groups.append(ExploreGroup(
                id: "__other__",
                name: String(localized: "Other", comment: "Explore rollup group for small entries"),
                bytes: rest.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) },
                fileCount: rest.count,
                detail: nil,
                paletteIndex: kept.count,
                children: []
            ))
        }
        return groups
    }

    // MARK: - By Age

    private static func buildAgeGroups(files: [FileRecord]) -> [ExploreGroup] {
        let now = Date()
        let buckets: [(id: String, title: String, upperBoundDays: Double?)] = [
            ("7d", String(localized: "Last 7 days", comment: "Explore age bucket"), 7),
            ("30d", String(localized: "Last 30 days", comment: "Explore age bucket"), 30),
            ("90d", String(localized: "Last 90 days", comment: "Explore age bucket"), 90),
            ("1y", String(localized: "Last year", comment: "Explore age bucket"), 365),
            ("older", String(localized: "Over a year ago", comment: "Explore age bucket"), nil),
        ]
        var bucketed: [String: [FileRecord]] = [:]
        var unknown: [FileRecord] = []
        for file in files {
            guard let touched = lastTouchedDate(for: file) else {
                unknown.append(file)
                continue
            }
            let days = now.timeIntervalSince(touched) / 86_400
            if days < 0 {
                bucketed["7d", default: []].append(file)
            } else if days <= 7 {
                bucketed["7d", default: []].append(file)
            } else if days <= 30 {
                bucketed["30d", default: []].append(file)
            } else if days <= 90 {
                bucketed["90d", default: []].append(file)
            } else if days <= 365 {
                bucketed["1y", default: []].append(file)
            } else {
                bucketed["older", default: []].append(file)
            }
        }
        var groups: [ExploreGroup] = []
        for (index, bucket) in buckets.enumerated() {
            guard let members = bucketed[bucket.id], !members.isEmpty else {
                continue
            }
            groups.append(ExploreGroup(
                id: "age:\(bucket.id)",
                name: bucket.title,
                bytes: members.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) },
                fileCount: members.count,
                detail: nil,
                paletteIndex: index,
                children: []
            ))
        }
        if !unknown.isEmpty {
            groups.append(ExploreGroup(
                id: "age:unknown",
                name: String(localized: "Unknown date", comment: "Explore age bucket for files without dates"),
                bytes: unknown.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) },
                fileCount: unknown.count,
                detail: nil,
                paletteIndex: buckets.count,
                children: []
            ))
        }
        return groups
    }

    /// Most recent evidence the file was touched; nil when no date is known.
    static func lastTouchedDate(for file: FileRecord) -> Date? {
        [file.lastOpenedAt, file.modifiedAt, file.createdAt].compactMap { $0 }.max()
    }

    /// Large files quiet for a long time — the Age Map spotlight list.
    static func bigUntouchedFiles(in files: [FileRecord], limit: Int = 10) -> [FileRecord] {
        let cutoff = Date().addingTimeInterval(-Double(untouchedThresholdDays) * 86_400)
        return files
            .filter { $0.sizeBytes >= bigFileThresholdBytes }
            .filter { file in
                guard let touched = lastTouchedDate(for: file) else {
                    return true
                }
                return touched < cutoff
            }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(max(1, limit))
            .map { $0 }
    }

    // MARK: - Sectors

    private static func appendSectors(
        group: ExploreGroup,
        depth: Int,
        start: Double,
        sweep: Double,
        maxDepth: Int,
        maxChildren: Int,
        into out: inout [SunburstSector]
    ) {
        guard sweep > 0, depth <= maxDepth else {
            return
        }
        out.append(SunburstSector(
            id: "\(group.id)#\(depth)",
            name: group.name,
            bytes: group.bytes,
            fileCount: group.fileCount,
            depth: depth,
            startFraction: start,
            endFraction: start + sweep,
            paletteIndex: group.paletteIndex,
            usesFolderPastel: group.usesFolderPastel
        ))
        let kids = Array(group.children.prefix(max(1, maxChildren)))
        guard !kids.isEmpty else {
            return
        }
        let kidsTotal = kids.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
        guard kidsTotal > 0 else {
            return
        }
        var cursor = start
        for kid in kids {
            let kidSweep = sweep * Double(max(0, kid.bytes)) / Double(kidsTotal)
            appendSectors(
                group: kid,
                depth: depth + 1,
                start: cursor,
                sweep: kidSweep,
                maxDepth: maxDepth,
                maxChildren: maxChildren,
                into: &out
            )
            cursor += kidSweep
        }
    }
}
