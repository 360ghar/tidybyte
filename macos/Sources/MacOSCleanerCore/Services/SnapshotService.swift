import Foundation
import os

/// One folder whose usage changed between two storage snapshots, ranked by
/// signed byte delta (growth first). Negative deltas are shrinkage.
public struct SnapshotFolderDelta: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var olderBytes: Int64
    public var newerBytes: Int64
    public var deltaBytes: Int64

    public init(path: String, olderBytes: Int64, newerBytes: Int64) {
        self.path = path
        self.olderBytes = olderBytes
        self.newerBytes = newerBytes
        self.deltaBytes = newerBytes - olderBytes
    }
}

/// Which folders grew (or shrank) between two snapshots, plus the category
/// shift behind the headline delta.
public struct SnapshotDiff: Sendable, Equatable {
    public var older: StorageSnapshot
    public var newer: StorageSnapshot
    public var totalDeltaBytes: Int64
    /// All changed root paths, growth-first; shrinkage trails at the end.
    public var folderDeltas: [SnapshotFolderDelta]
    /// Category deltas, growth-first, excluding unchanged categories.
    public var categoryDeltas: [(category: FindingCategory, deltaBytes: Int64)]

    public static func == (lhs: SnapshotDiff, rhs: SnapshotDiff) -> Bool {
        lhs.older.id == rhs.older.id
            && lhs.newer.id == rhs.newer.id
            && lhs.totalDeltaBytes == rhs.totalDeltaBytes
            && lhs.folderDeltas == rhs.folderDeltas
            && lhs.categoryDeltas.map(\.deltaBytes) == rhs.categoryDeltas.map(\.deltaBytes)
            && lhs.categoryDeltas.map(\.category) == rhs.categoryDeltas.map(\.category)
    }
}

public enum SnapshotServiceError: Error, LocalizedError, Sendable {
    case sameSnapshot
    case snapshotMissing

    public var errorDescription: String? {
        switch self {
        case .sameSnapshot:
            String(localized: "Select two different snapshots to compare.", comment: "Snapshot diff same-snapshot error")
        case .snapshotMissing:
            String(localized: "One of the selected snapshots no longer exists.", comment: "Snapshot diff missing-snapshot error")
        }
    }
}

/// Read-only snapshot history service. Snapshots are written by
/// ScanOrchestrator after every scan; this service lists them and diffs any
/// pair so the Snapshots tab can show which folders grew. No background work,
/// no auto-delete — strictly list and diff.
public actor SnapshotService {
    private let store: SQLiteStore
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "SnapshotService")

    public init(store: SQLiteStore) {
        self.store = store
    }

    /// Newest-first snapshot history for the Snapshots tab picker.
    public func listSnapshots(limit: Int = 30) async throws -> [StorageSnapshot] {
        try await store.recentSnapshots(limit: limit)
    }

    /// Diffs two snapshots by ID: folder growth ranked from `bytesByRootPath`
    /// (union of old and new paths, missing side counts as zero), category
    /// shifts from `bytesByCategory`, and the headline total delta. Pure and
    /// synchronous once loaded — safe to call from tests without a store.
    public func diffSnapshot(olderID: String, newerID: String) async throws -> SnapshotDiff {
        guard olderID != newerID else {
            throw SnapshotServiceError.sameSnapshot
        }
        let snapshots = try await store.recentSnapshots(limit: 200)
        guard let older = snapshots.first(where: { $0.id == olderID }),
              let newer = snapshots.first(where: { $0.id == newerID }) else {
            throw SnapshotServiceError.snapshotMissing
        }
        // Chronological order regardless of which the user picked first, so
        // "growth" always means newer-minus-older.
        if older.createdAt <= newer.createdAt {
            return Self.diff(older: older, newer: newer)
        } else {
            return Self.diff(older: newer, newer: older)
        }
    }

    /// Pure diff over two snapshots. Growth-first ordering puts the folders
    /// eating the disk at the top; shrinkage trails so cleanup wins stay
    /// visible without burying growth.
    public nonisolated static func diff(older: StorageSnapshot, newer: StorageSnapshot) -> SnapshotDiff {
        let allPaths = Set(older.bytesByRootPath.keys).union(newer.bytesByRootPath.keys)
        let folderDeltas = allPaths.compactMap { path -> SnapshotFolderDelta? in
            let oldBytes = older.bytesByRootPath[path] ?? 0
            let newBytes = newer.bytesByRootPath[path] ?? 0
            guard oldBytes != newBytes else { return nil }
            return SnapshotFolderDelta(path: path, olderBytes: oldBytes, newerBytes: newBytes)
        }
        .sorted {
            if $0.deltaBytes != $1.deltaBytes { return $0.deltaBytes > $1.deltaBytes }
            return $0.path < $1.path
        }

        let allCategories = Set(older.bytesByCategory.keys).union(newer.bytesByCategory.keys)
        let categoryDeltas = allCategories.compactMap { category -> (FindingCategory, Int64)? in
            let delta = (newer.bytesByCategory[category] ?? 0) - (older.bytesByCategory[category] ?? 0)
            guard delta != 0 else { return nil }
            return (category, delta)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.rawValue < $1.0.rawValue
        }

        return SnapshotDiff(
            older: older,
            newer: newer,
            totalDeltaBytes: newer.totalBytes - older.totalBytes,
            folderDeltas: folderDeltas,
            categoryDeltas: categoryDeltas
        )
    }
}
