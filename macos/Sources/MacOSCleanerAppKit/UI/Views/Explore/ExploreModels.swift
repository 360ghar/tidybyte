import Foundation
import MacOSCleanerCore

// MARK: - Subtree index

/// Pure helpers that derive directory rollups from an immutable file list.
/// Mirrors the prefix-based approach in CleanerRuleEngine without duplicating
/// its actor state; all members are static so views can call them directly.
enum ExploreSubtreeIndex {
    /// Total reclaimable bytes under every ancestor path. Only non-container
    /// records contribute, so directory records never double-count their own
    /// allocation size on top of their children.
    static func totals(files: [FileRecord]) -> [String: Int64] {
        var totals: [String: Int64] = [:]
        for file in files {
            let bytes = max(0, file.sizeBytes)
            guard bytes > 0, file.kind != .directory, file.kind != .package else {
                continue
            }
            var current = file.url.deletingLastPathComponent().standardizedFileURL.path
            var depth = 0
            while depth < 64 {
                totals[current, default: 0] += bytes
                let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
                if parent == current {
                    break
                }
                current = parent
                depth += 1
            }
        }
        return totals
    }

    /// Effective on-disk size for a record: the indexed subtree total for
    /// containers, the scanned size for files.
    static func subtreeBytes(for record: FileRecord, totals: [String: Int64]) -> Int64 {
        if record.kind == .directory || record.kind == .package {
            return totals[record.displayPath] ?? max(0, record.sizeBytes)
        }
        return max(0, record.sizeBytes)
    }

    static func parentPath(of displayPath: String) -> String {
        (displayPath as NSString).deletingLastPathComponent
    }

    /// Every scanned record strictly below the given directory path.
    static func descendants(ofParentPath parentPath: String, in files: [FileRecord]) -> [FileRecord] {
        let prefix = parentPath + "/"
        return files.filter { $0.displayPath.hasPrefix(prefix) }
    }

    /// Scanned records whose direct parent is the given directory path.
    static func directChildren(ofParentPath parentPath: String, in files: [FileRecord]) -> [FileRecord] {
        files.filter { ($0.displayPath as NSString).deletingLastPathComponent == parentPath }
    }
}

// MARK: - Live size probe

/// Reads both size keys for a URL in one stat call. FileRecord only carries a
/// single size, so APFS compression savings are probed live at selection time
/// and hidden when the filesystem cannot provide them.
enum FileSizeProbe {
    struct Sizes: Equatable, Sendable {
        var logical: Int64?
        var allocated: Int64?
    }

    static func sizes(for url: URL) -> Sizes {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Sizes(
            logical: values?.fileSize.map(Int64.init),
            allocated: values?.totalFileAllocatedSize.map(Int64.init)
        )
    }
}

// MARK: - Disk gauge data

/// Live home-volume capacity snapshot. The persisted Volume rows have no
/// loader (SQLiteStore only saves them during scans), so the gauge reads the
/// filesystem directly.
enum DiskGaugeData {
    struct Snapshot: Equatable, Sendable {
        var totalBytes: Int64?
        var freeBytes: Int64?
    }

    /// Free space counts purgeable space, as System Settings › Storage does.
    static func currentHomeVolume() -> Snapshot {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: keys)
        return Snapshot(
            totalBytes: values?.volumeTotalCapacity.map(Int64.init),
            freeBytes: values?.volumeAvailableCapacityForImportantUsage
        )
    }
}

