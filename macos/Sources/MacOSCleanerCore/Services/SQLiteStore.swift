import Foundation
import os
import SQLite3

public enum DatabaseError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case migrationFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case databaseUnavailable
    case checkpointFailed(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): message
        case .migrationFailed(let message): message
        case .prepareFailed(let message): message
        case .bindFailed(let message): message
        case .stepFailed(let message): message
        case .encodingFailed(let message): message
        case .decodingFailed(let message): message
        case .databaseUnavailable: String(localized: "SQLite database is unavailable.", comment: "Error when SQLite database is unavailable")
        case .checkpointFailed(let message): message
        case .exportFailed(let message): message
        }
    }
}

public enum SQLiteTable: String, CaseIterable, Sendable {
    case scanSessions = "scan_sessions"
    case volumes
    case fileRecords = "file_records"
    case fingerprints
    case contentSummaries = "content_summaries"
    case projects
    case relationshipEdges = "relationship_edges"
    case findings
    case recommendations
    case plans
    case plannedActions = "planned_actions"
    case operationLogs = "operation_logs"
    case undoRecords = "undo_records"
    case memoryRules = "memory_rules"
    case regretEvents = "regret_events"
    case storageSnapshots = "storage_snapshots"
    case fileHashes = "file_hashes"
    case cleanupState = "cleanup_state"
    case cleanupActivity = "cleanup_activity"
    case cleanupSnapshots = "cleanup_snapshots"
}

/// Persistent content-hash cache entry. Keyed by normalized path; a cached
/// hash is valid only when size and mtime both match, so edits invalidate it.
public struct FileHashCacheEntry: Codable, Sendable {
    public var path: String
    public var sizeBytes: Int64
    public var modifiedAt: Date?
    public var fullHash: String

    public init(path: String, sizeBytes: Int64, modifiedAt: Date?, fullHash: String) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.fullHash = fullHash
    }
}

private enum SQLiteValue {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
}

public actor SQLiteStore {
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "SQLiteStore")
    private let databaseURL: URL
    // SAFETY: `database` is an unsafe pointer that cannot conform to Sendable.
    // Actor isolation protects all public methods. SQLITE_OPEN_FULLMUTEX ensures
    // the SQLite connection itself is thread-safe. The `nonisolated(unsafe)` is
    // required only for deinit access via withExtendedLifetime.
    private nonisolated(unsafe) var database: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    // SAFETY: `isClosed` is accessed from the nonisolated deinit to avoid double-close.
    // Only mutated under actor isolation (via close()). deinit reads it after
    // withExtendedLifetime ensures the object stays alive, so no data race occurs.
    private nonisolated(unsafe) var isClosed = false
    private let isUnavailable: Bool
    // Tracks whether an explicit transaction is open on this connection so nested
    // bulk-write paths (e.g. savePlan calling saveAll) skip BEGIN/COMMIT and reuse
    // the outer transaction. Only mutated under actor isolation.
    private var isInTransaction = false

    public init(databaseURL: URL? = nil) throws {
        let resolvedURL = try databaseURL ?? Self.defaultDatabaseURL()
        self.databaseURL = resolvedURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.isUnavailable = false
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        // SQLite recognizes the literal string ":memory:" as a special in-memory database
        // identifier. However, `URL(fileURLWithPath: ":memory:").path` resolves to an
        // absolute filesystem path (e.g. "/Users/.../:memory:"), which SQLite treats as a
        // regular file — creating a large on-disk file instead of an in-memory DB. Detect
        // this case and pass the raw ":memory:" string to sqlite3_open_v2.
        let openPath: String
        if resolvedURL.lastPathComponent == ":memory:" {
            openPath = ":memory:"
        } else {
            openPath = resolvedURL.path
        }

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            openPath,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? String(localized: "Unable to open SQLite database.", comment: "Fallback error when SQLite open fails with no message")
            if let handle {
                sqlite3_close(handle)
            }
            throw DatabaseError.openFailed(message)
        }
        self.database = handle
        try Self.migrate(database: handle)
    }

    deinit {
        withExtendedLifetime(self) {
            guard !isUnavailable, let db = unsafeDatabasePointer() else { return }
            sqlite3_close(db)
        }
    }

    /// Returns the raw database pointer for use in nonisolated contexts (e.g., deinit).
    /// This is intentionally nonisolated to allow safe cleanup during deallocation.
    nonisolated func unsafeDatabasePointer() -> OpaquePointer? {
        database
    }

    public func close() {
        guard !isClosed, !isUnavailable, let database else { return }
        sqlite3_close(database)
        self.database = nil
        isClosed = true
    }

    public func saveCleanupState<T: Encodable & Sendable>(_ value: T, key: String) throws {
        try upsert(JSONEncoder().encode(value), id: key, table: .cleanupState)
    }

    public func loadCleanupState<T: Decodable & Sendable>(_ type: T.Type, key: String) throws -> T? {
        guard let data = try selectJSON("SELECT json FROM cleanup_state WHERE id = ?",
                                        values: [.text(key)], as: Data.self).first else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    public func resetReviewHistory() throws {
        try execute("DELETE FROM cleanup_state WHERE id LIKE 'review:%' OR id = 'draft'", values: [])
    }

    public func saveActivity(_ event: ActivityEvent) throws {
        try upsert(JSONEncoder().encode(event), id: event.id, table: .cleanupActivity)
    }

    public func cleanupActivity() throws -> [ActivityEvent] {
        try selectJSON("SELECT json FROM cleanup_activity ORDER BY created_at DESC", values: [], as: Data.self)
            .map { try JSONDecoder().decode(ActivityEvent.self, from: $0) }
    }

    public func cleanupActivity(id: String) throws -> ActivityEvent? {
        guard let data = try selectJSON(
            "SELECT json FROM cleanup_activity WHERE id = ?", values: [.text(id)], as: Data.self).first else {
            return nil
        }
        return try JSONDecoder().decode(ActivityEvent.self, from: data)
    }

    public func saveCleanupSnapshot(_ snapshot: CleanupSnapshot) throws {
        try upsert(JSONEncoder().encode(snapshot), id: snapshot.id, table: .cleanupSnapshots)
    }

    public func cleanupSnapshots(scopeID: String) throws -> [CleanupSnapshot] {
        try selectJSON("SELECT json FROM cleanup_snapshots ORDER BY created_at", values: [], as: Data.self)
            .map { try JSONDecoder().decode(CleanupSnapshot.self, from: $0) }
            .filter { $0.scopeID == scopeID }
    }

    /// Returns the file URL of the SQLite database.
    public func databaseFileURL() -> URL {
        databaseURL
    }

    /// Runs a TRUNCATE WAL checkpoint so all committed writes are folded into the
    /// main database file, making it safe to copy with FileManager. Uses the
    /// sqlite3 C API directly; no SQL strings are built.
    public func checkpointWAL() throws {
        guard !isUnavailable, let database else {
            throw DatabaseError.databaseUnavailable
        }
        let result = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        // SQLITE_BUSY means another connection holds the WAL, so the checkpoint
        // could not complete. exportCopy(to:) still produces a consistent snapshot
        // via the backup API in that case; only hard failures throw here.
        guard result == SQLITE_OK || result == SQLITE_BUSY else {
            throw DatabaseError.checkpointFailed(lastErrorMessage())
        }
    }

    /// Exports a consistent snapshot of the database to `destination` using the
    /// SQLite backup API (sqlite3_backup_init/step/finish). The backup reads the
    /// committed state across the main file and the WAL, so the copy is complete
    /// even without a preceding checkpoint. Creates the destination directory if
    /// needed and replaces any existing file at `destination`.
    public func exportCopy(to destination: URL) throws {
        guard !isUnavailable, let source = database else {
            throw DatabaseError.databaseUnavailable
        }
        // Fold WAL content into the main file first so the destination is also a
        // complete standalone database if it is later copied with FileManager.
        try checkpointWAL()

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        var destinationHandle: OpaquePointer?
        let openResult = sqlite3_open_v2(destination.path, &destinationHandle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        guard openResult == SQLITE_OK, let destinationHandle else {
            let message = destinationHandle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? String(localized: "Unable to open export destination.", comment: "Error when opening the export destination database")
            if let destinationHandle {
                sqlite3_close(destinationHandle)
            }
            throw DatabaseError.exportFailed(message)
        }

        guard let backup = sqlite3_backup_init(destinationHandle, "main", source, "main") else {
            let message = String(cString: sqlite3_errmsg(destinationHandle))
            sqlite3_close(destinationHandle)
            throw DatabaseError.exportFailed(message)
        }

        var stepResult = sqlite3_backup_step(backup, -1)
        while stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED {
            stepResult = sqlite3_backup_step(backup, -1)
        }
        guard stepResult == SQLITE_DONE else {
            _ = sqlite3_backup_finish(backup)
            sqlite3_close(destinationHandle)
            throw DatabaseError.exportFailed(String(localized: "Database export failed with code \(stepResult).", comment: "Error when a database backup step fails"))
        }
        let finishResult = sqlite3_backup_finish(backup)
        sqlite3_close(destinationHandle)
        guard finishResult == SQLITE_OK else {
            throw DatabaseError.exportFailed(String(localized: "Database export could not be finalized.", comment: "Error when finalizing a database backup"))
        }
    }

    public static func inMemory() throws -> SQLiteStore {
        try SQLiteStore(databaseURL: URL(fileURLWithPath: ":memory:"))
    }

    public static var unavailable: SQLiteStore {
        let store = SQLiteStore(
            databaseURL: URL(fileURLWithPath: "/dev/null"),
            encoder: JSONEncoder(),
            decoder: JSONDecoder(),
            database: nil,
            isUnavailable: true
        )
        return store
    }

    private init(databaseURL: URL, encoder: JSONEncoder, decoder: JSONDecoder, database: OpaquePointer?, isUnavailable: Bool) {
        self.databaseURL = databaseURL
        self.encoder = encoder
        self.decoder = decoder
        self.database = database
        self.isUnavailable = isUnavailable
    }

    public nonisolated static func defaultDatabaseURL() throws -> URL {
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseURL: URL
        if let appSupportDir {
            baseURL = appSupportDir
        } else {
            baseURL = FileManager.default.temporaryDirectory
            logger.warning("Application Support directory unavailable; falling back to temp directory for database storage. Data will not persist.")
        }
        let directory = baseURL.appendingPathComponent(AppIdentity.supportFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(AppIdentity.databaseFileName, isDirectory: false)
    }

    public func deleteAllData() throws {
        try withTransaction {
            for table in SQLiteTable.allCases.reversed() {
                try execute("DELETE FROM \(table.rawValue)", values: [])
            }
        }
    }

    public func saveScanSession(_ session: ScanSession) throws {
        try upsert(session, id: session.id, table: .scanSessions)
    }

    public func saveVolume(_ volume: Volume) throws {
        try upsert(volume, id: volume.id, table: .volumes)
    }

    public func saveFileRecords(_ records: [FileRecord]) throws {
        try saveAll(records, idKeyPath: \.id, table: .fileRecords)
    }

    public func saveFingerprints(_ fingerprints: [FileFingerprint]) throws {
        try saveAll(fingerprints, idKeyPath: \.fileID, table: .fingerprints)
    }

    public func saveContentSummaries(_ summaries: [ContentSummary]) throws {
        try saveAll(summaries, idKeyPath: \.fileID, table: .contentSummaries)
    }

    public func saveProjects(_ projects: [ProjectUnit]) throws {
        try saveAll(projects, idKeyPath: \.id, table: .projects)
    }

    public func saveRelationshipEdges(_ edges: [RelationshipEdge]) throws {
        try saveAll(edges, idKeyPath: \.id, table: .relationshipEdges)
    }

    public func saveFindings(_ findings: [Finding]) throws {
        try saveAll(findings, idKeyPath: \.id, table: .findings)
    }

    public func saveRecommendations(_ recommendations: [Recommendation]) throws {
        try saveAll(recommendations, idKeyPath: \.id, table: .recommendations)
    }

    public func savePlan(_ plan: Plan) throws {
        try withTransaction {
            try upsert(plan, id: plan.id, table: .plans)
            try saveAll(plan.actions, idKeyPath: \.id, table: .plannedActions)
        }
    }

    public func saveOperationLog(_ log: OperationLog) throws {
        try upsert(log, id: log.id, table: .operationLogs)
    }

    /// Batch-persists operation logs in a single transaction. Prefer this over
    /// repeated `saveOperationLog(_:)` calls when persisting many logs at once.
    public func saveOperationLogs(_ logs: [OperationLog]) throws {
        try saveAll(logs, idKeyPath: \.id, table: .operationLogs)
    }

    public func saveUndoRecord(_ undo: UndoRecord) throws {
        try upsert(undo, id: undo.id, table: .undoRecords)
    }

    /// Batch-persists undo records in a single transaction. Prefer this over
    /// repeated `saveUndoRecord(_:)` calls when persisting many records at once.
    public func saveUndoRecords(_ records: [UndoRecord]) throws {
        try saveAll(records, idKeyPath: \.id, table: .undoRecords)
    }

    public func saveMemoryRule(_ rule: MemoryRule) throws {
        try upsert(rule, id: rule.id, table: .memoryRules)
    }

    public func saveRegretEvent(_ event: RegretEvent) throws {
        try upsert(event, id: event.id, table: .regretEvents)
    }

    public func saveStorageSnapshot(_ snapshot: StorageSnapshot) throws {
        try upsert(snapshot, id: snapshot.id, table: .storageSnapshots)
    }

    public func saveFileHash(_ entry: FileHashCacheEntry) throws {
        try upsert(entry, id: entry.path, table: .fileHashes)
    }

    public func saveFileHashes(_ entries: [FileHashCacheEntry]) throws {
        try withTransaction {
            for entry in entries {
                try upsert(entry, id: entry.path, table: .fileHashes)
            }
        }
    }

    /// Cached full hash for `path`, valid only when size and mtime both match.
    /// Returns nil on any mismatch so the caller re-hashes.
    public func cachedFullHash(forPath path: String, sizeBytes: Int64, modifiedAt: Date?) throws -> String? {
        let rows: [FileHashCacheEntry] = try selectJSON(
            "SELECT json FROM \(SQLiteTable.fileHashes.rawValue) WHERE id = ? LIMIT 1",
            values: [.text(path)],
            as: FileHashCacheEntry.self
        )
        guard let entry = rows.first, entry.sizeBytes == sizeBytes else {
            return nil
        }
        switch (entry.modifiedAt, modifiedAt) {
        case (nil, nil):
            return entry.fullHash
        case let (expected?, actual?):
            return abs(actual.timeIntervalSince(expected)) <= 1 ? entry.fullHash : nil
        default:
            return nil
        }
    }

    /// File records for a path prefix, using the v5 file_path index instead of
    /// a full-table JSON scan.
    public func loadFileRecords(matchingPrefix prefix: String) throws -> [FileRecord] {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.fileRecords.rawValue) WHERE file_path = ? OR file_path LIKE ? ORDER BY created_at",
            values: [.text(prefix), .text(prefix + "/%")],
            as: FileRecord.self
        )
    }

    private func saveAll<T: Encodable>(_ items: [T], idKeyPath: KeyPath<T, String>, table: SQLiteTable) throws {
        // Batch all INSERTs inside one explicit transaction. Per-row autocommit
        // inserts are quadratic for large batches (each row pays fsync); a single
        // BEGIN IMMEDIATE/COMMIT keeps bulk persistence linear and atomic.
        try withTransaction {
            for item in items {
                // One pool per row: a scan saves up to a million records in this loop.
                try autoreleasepool { try upsert(item, id: item[keyPath: idKeyPath], table: table) }
            }
        }
    }

    public func loadFileRecords(for sessionID: String) throws -> [FileRecord] {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.fileRecords.rawValue) WHERE scan_session_id = ? ORDER BY created_at",
            values: [.text(sessionID)],
            as: FileRecord.self
        )
    }

    public func loadPlan(id: String) throws -> Plan? {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.plans.rawValue) WHERE id = ? LIMIT 1",
            values: [.text(id)],
            as: Plan.self
        ).first
    }

    public func loadMemoryRules() throws -> [MemoryRule] {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.memoryRules.rawValue) ORDER BY created_at DESC",
            values: [],
            as: MemoryRule.self
        )
    }

    public func loadUndoRecords() throws -> [UndoRecord] {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.undoRecords.rawValue) ORDER BY created_at DESC",
            values: [],
            as: UndoRecord.self
        )
    }

    /// Loads only the undo records that belong to the same operation log
    /// (i.e. sibling records for the same action). Uses the dedicated
    /// `operation_log_id` column added in schema v3.
    public func loadUndoRecords(operationLogID: String) throws -> [UndoRecord] {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.undoRecords.rawValue) WHERE operation_log_id = ? ORDER BY created_at DESC",
            values: [.text(operationLogID)],
            as: UndoRecord.self
        )
    }

    /// Interrupted operations: pending undo records older than the grace window,
    /// with their operation logs. The startup sweep surfaces these so a crash
    /// between the filesystem mutation and the finalize write leaves a visible,
    /// recoverable trail (original path lives in the log's beforeState).
    public func loadStalePendingUndos(olderThan cutoff: Date) throws -> [(undo: UndoRecord, log: OperationLog?)] {
        guard !isUnavailable else {
            throw DatabaseError.databaseUnavailable
        }
        let records: [UndoRecord] = try selectJSON(
            "SELECT json FROM \(SQLiteTable.undoRecords.rawValue) WHERE status = 'pending' AND created_at < ?",
            values: [.real(cutoff.timeIntervalSince1970)],
            as: UndoRecord.self
        )
        return try records.map { undo in
            (undo, try loadOperationLog(id: undo.operationLogID))
        }
    }

    public func loadOperationLog(id: String) throws -> OperationLog? {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.operationLogs.rawValue) WHERE id = ? LIMIT 1",
            values: [.text(id)],
            as: OperationLog.self
        ).first
    }

    public func recentPlans(limit: Int = 10) throws -> [Plan] {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.plans.rawValue) ORDER BY created_at DESC LIMIT ?",
            values: [.integer(Int64(limit))],
            as: Plan.self
        )
    }

    public func recentSnapshots(limit: Int = 30) throws -> [StorageSnapshot] {
        try selectJSON(
            "SELECT json FROM \(SQLiteTable.storageSnapshots.rawValue) ORDER BY created_at DESC LIMIT ?",
            values: [.integer(Int64(limit))],
            as: StorageSnapshot.self
        )
    }

    public func snapshotComparison() async throws -> (current: StorageSnapshot?, previous: StorageSnapshot?, delta: Int64) {
        let snapshots = try await recentSnapshots(limit: 2)
        let current = snapshots.first
        let previous = snapshots.count > 1 ? snapshots[1] : nil
        let delta = (current?.totalBytes ?? 0) - (previous?.totalBytes ?? 0)
        return (current, previous, delta)
    }

    public func purgeOldData(keepingDays: Int = 90) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -keepingDays, to: Date())?.timeIntervalSince1970 ?? 0
        // Delete old scan sessions (never purge running sessions). `status`
        // lives inside the JSON blob (the table schema is id/scan_session_id/
        // created_at/json), so it is read via json_extract.
        try execute(
            "DELETE FROM \(SQLiteTable.scanSessions.rawValue) WHERE created_at < ? AND json_extract(json, '$.status') != 'running'",
            values: [.real(cutoffDate)]
        )
        // Delete orphaned records in all session-scoped tables (no matching session).
        // Tables with a scan_session_id column that links to scan_sessions.
        let sessionScopedTables: [SQLiteTable] = [
            .fileRecords, .contentSummaries, .findings, .recommendations,
            .plannedActions, .relationshipEdges
        ]
        for table in sessionScopedTables {
            try execute("DELETE FROM \(table.rawValue) WHERE scan_session_id NOT IN (SELECT id FROM \(SQLiteTable.scanSessions.rawValue))", values: [])
        }
        // Delete orphaned fingerprints (linked to file_records via id=fileID; FileFingerprint
        // has no scanSessionID so scan_session_id is always NULL and the old join was a no-op).
        try execute("DELETE FROM \(SQLiteTable.fingerprints.rawValue) WHERE id NOT IN (SELECT id FROM \(SQLiteTable.fileRecords.rawValue))", values: [])
        // Delete orphaned plans (linked to scan_sessions via scan_session_id).
        try execute("DELETE FROM \(SQLiteTable.plans.rawValue) WHERE scan_session_id NOT IN (SELECT id FROM \(SQLiteTable.scanSessions.rawValue))", values: [])

        // Undo records are not session-scoped and were never purged, so they
        // accumulated forever. Purge records that can never be restored:
        // expired/failed status, or available records whose validity window has
        // passed. Uses a full-table load + Swift filter because purge is rare
        // and the filter logic (validUntil date comparison) is simpler in Swift
        // than in SQLite's JSON1 date parsing.
        let allUndos = try loadUndoRecords()
        let now = Date()
        for undo in allUndos {
            let expired = undo.status == .expired || undo.status == .failed
            let validUntilExpired = undo.validUntil.map { $0 < now } ?? false
            if expired || validUntilExpired {
                try execute("DELETE FROM \(SQLiteTable.undoRecords.rawValue) WHERE id = ?", values: [.text(undo.id)])
            }
        }
        // Delete orphaned operation logs: their undo records were just purged
        // (or never existed). Only delete logs older than the cutoff so very
        // recent logs without a linked undo (e.g. in-flight operations) are not
        // accidentally removed.
        try execute(
            "DELETE FROM \(SQLiteTable.operationLogs.rawValue) WHERE created_at < ? AND id NOT IN (SELECT operation_log_id FROM \(SQLiteTable.undoRecords.rawValue) WHERE operation_log_id IS NOT NULL)",
            values: [.real(cutoffDate)]
        )

        // Vacuum to reclaim space
        try execute("VACUUM", values: [])
    }

    private static func migrate(database: OpaquePointer) throws {
        // WAL mode may fail on some filesystems (network drives, certain configurations).
        // Fall back to non-WAL mode if WAL cannot be enabled.
        do {
            try executeMigration("PRAGMA journal_mode=WAL", database: database)
        } catch {
            Self.logger.warning("WAL mode failed, falling back to non-WAL mode: \(error.localizedDescription)")
        }
        try executeMigration("PRAGMA foreign_keys=ON", database: database)
        // synchronous=FULL pairs with WAL so a power loss cannot lose a committed
        // undo trail — the durability guarantee the executor's write-ahead
        // persistence depends on.
        try executeMigration("PRAGMA synchronous=FULL", database: database)

        // Idempotent base schema. CREATE TABLE/INDEX IF NOT EXISTS is safe to run
        // on any existing database, so base tables are always ensured regardless
        // of user_version. This makes opening an older or partially migrated DB
        // self-healing without redesigning the schema.
        for table in SQLiteTable.allCases {
            try executeMigration("""
            CREATE TABLE IF NOT EXISTS \(table.rawValue) (
                id TEXT PRIMARY KEY NOT NULL,
                scan_session_id TEXT,
                created_at REAL NOT NULL,
                json TEXT NOT NULL
            )
            """, database: database)
            try executeMigration("CREATE INDEX IF NOT EXISTS idx_\(table.rawValue)_scan_session_id ON \(table.rawValue)(scan_session_id)", database: database)
            try executeMigration("CREATE INDEX IF NOT EXISTS idx_\(table.rawValue)_created_at ON \(table.rawValue)(created_at)", database: database)
        }

        // Schema version tracking. Any future schema additions (e.g.
        // ALTER TABLE ... ADD COLUMN) must be guarded by a user_version check so
        // they run exactly once on existing databases.
        let currentVersion = try getUserVersion(database: database)

        // v2: initial tracked version (base schema above is idempotent).
        // v3: undo_records.operation_log_id column + index + backfill, so undo
        //     sibling lookups and orphan purges do not require full-table scans.
        if currentVersion < 2 {
            try setUserVersion(2, database: database)
        }
        if currentVersion < 3 {
            try executeMigration("ALTER TABLE undo_records ADD COLUMN operation_log_id TEXT", database: database)
            // Backfill from the JSON blob for rows written before the column existed.
            // json_extract is part of SQLite's JSON1 extension (bundled on macOS).
            try executeMigration(
                "UPDATE undo_records SET operation_log_id = json_extract(json, '$.operationLogID') WHERE operation_log_id IS NULL",
                database: database
            )
            try executeMigration("CREATE INDEX IF NOT EXISTS idx_undo_records_operation_log_id ON undo_records(operation_log_id)", database: database)
            try setUserVersion(3, database: database)
        }
        if currentVersion < 4 {
            // v4: undo_records.status column so the startup sweep can find
            // interrupted (pending) operations without loading every JSON blob.
            try executeMigration("ALTER TABLE undo_records ADD COLUMN status TEXT", database: database)
            try executeMigration(
                "UPDATE undo_records SET status = json_extract(json, '$.status') WHERE status IS NULL",
                database: database
            )
            try executeMigration("CREATE INDEX IF NOT EXISTS idx_undo_records_status ON undo_records(status)", database: database)
            try setUserVersion(4, database: database)
        }
        if currentVersion < 5 {
            // v5: file_records.file_path column + index so path lookups and
            // stable-ID derivation avoid full-table JSON scans. Backfilled from
            // the JSON blob for rows written before the column existed.
            try executeMigration("ALTER TABLE file_records ADD COLUMN file_path TEXT", database: database)
            try executeMigration(
                "UPDATE file_records SET file_path = json_extract(json, '$.url') WHERE file_path IS NULL",
                database: database
            )
            try executeMigration("CREATE INDEX IF NOT EXISTS idx_file_records_file_path ON file_records(file_path)", database: database)
            // v5: persistent content-hash cache so re-scans skip re-hashing
            // unchanged files. Keyed by path; validity is (size, mtime).
            try executeMigration("""
            CREATE TABLE IF NOT EXISTS file_hashes (
                id TEXT PRIMARY KEY NOT NULL,
                scan_session_id TEXT,
                created_at REAL NOT NULL,
                json TEXT NOT NULL
            )
            """, database: database)
            try executeMigration("CREATE INDEX IF NOT EXISTS idx_file_hashes_scan_session_id ON file_hashes(scan_session_id)", database: database)
            try executeMigration("CREATE INDEX IF NOT EXISTS idx_file_hashes_created_at ON file_hashes(created_at)", database: database)
            try setUserVersion(5, database: database)
        }
        if currentVersion < 6 {
            // Cleanup tables are additive and deliberately excluded from scan retention.
            try setUserVersion(6, database: database)
        }
    }

    private static func getUserVersion(database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int(statement, 0)
        }
        return 0
    }

    private static func setUserVersion(_ version: Int32, database: OpaquePointer) throws {
        // PRAGMA statements do not accept bound parameters, so the version must be
        // inlined. `version` is a hardcoded code constant, never user input, so this
        // cannot be a SQL-injection vector.
        let sql = "PRAGMA user_version = \(version)"
        try executeMigration(sql, database: database)
    }

    private static func executeMigration(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(localized: "Unknown SQLite migration error.", comment: "Fallback error for unknown SQLite migration failure")
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
            throw DatabaseError.migrationFailed(message)
        }
    }

    private func upsert<T: Encodable>(_ object: T, id: String, table: SQLiteTable) throws {
        let data: Data
        do {
            data = try encoder.encode(object)
        } catch {
            throw DatabaseError.encodingFailed(error.localizedDescription)
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw DatabaseError.encodingFailed(String(localized: "Encoded JSON was not valid UTF-8.", comment: "Error when encoded JSON is not valid UTF-8"))
        }
        let scanSessionID = extractScanSessionID(from: object)
        let operationLogID = extractOperationLogID(from: object)
        let filePath = extractFilePath(from: object)
        // Use ON CONFLICT to preserve the original created_at timestamp on updates.
        // INSERT OR REPLACE would delete-and-reinsert, resetting created_at and
        // making purgeOldData() unable to age-out records that were re-saved.
        let sql: String
        let values: [SQLiteValue]
        if table == .undoRecords {
            // undo_records carries dedicated columns (v3: operation_log_id,
            // v4: status) so sibling lookups and the pending-operations sweep
            // avoid full-table JSON scans.
            sql = """
            INSERT INTO \(table.rawValue) (id, scan_session_id, operation_log_id, status, created_at, json)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                json = excluded.json,
                scan_session_id = excluded.scan_session_id,
                operation_log_id = excluded.operation_log_id,
                status = excluded.status
            """
            values = [
                .text(id),
                scanSessionID.map { .text($0) } ?? .null,
                operationLogID.map { .text($0) } ?? .null,
                (object as? UndoRecord).map { .text($0.status.rawValue) } ?? .null,
                .real(Date().timeIntervalSince1970),
                .text(json)
            ]
        } else if table == .fileRecords {
            // file_records carries file_path (v5) so prefix lookups use the
            // index instead of scanning every JSON blob.
            sql = """
            INSERT INTO \(table.rawValue) (id, scan_session_id, file_path, created_at, json)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                json = excluded.json,
                scan_session_id = excluded.scan_session_id,
                file_path = excluded.file_path
            """
            values = [
                .text(id),
                scanSessionID.map { .text($0) } ?? .null,
                filePath.map { .text($0) } ?? .null,
                .real(Date().timeIntervalSince1970),
                .text(json)
            ]
        } else {
            sql = """
            INSERT INTO \(table.rawValue) (id, scan_session_id, created_at, json)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                json = excluded.json,
                scan_session_id = excluded.scan_session_id
            """
            values = [
                .text(id),
                scanSessionID.map { .text($0) } ?? .null,
                .real(Date().timeIntervalSince1970),
                .text(json)
            ]
        }
        try execute(sql, values: values)
    }

    private func extractOperationLogID<T>(from object: T) -> String? {
        (object as? UndoRecord)?.operationLogID
    }

    private func extractFilePath<T>(from object: T) -> String? {
        (object as? FileRecord)?.url.standardizedFileURL.path
    }

    private func extractScanSessionID<T>(from object: T) -> String? {
        // ScanSession uses its own id as the session identifier.
        if let value = object as? ScanSession {
            return value.id
        }
        // Types that belong to a scan session return its ID directly.
        if let value = object as? ScanSessionScoped {
            return value.scanSessionID
        }
        return nil
    }

    private func execute(_ sql: String, values: [SQLiteValue]) throws {
        guard !isUnavailable else {
            throw DatabaseError.databaseUnavailable
        }
        var statement: OpaquePointer?
        guard let database else {
            throw DatabaseError.databaseUnavailable
        }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer {
            sqlite3_finalize(statement)
        }
        try bind(values, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }
    }

    /// Runs `body` inside one explicit transaction (BEGIN IMMEDIATE/COMMIT with
    /// ROLLBACK on error). Nested calls reuse the already-open outer transaction
    /// instead of opening another one, so callers can compose bulk persist paths
    /// (e.g. savePlan wrapping saveAll) without transaction conflicts.
    private func withTransaction<T>(_ body: () throws -> T) throws -> T {
        guard !isInTransaction else {
            return try body()
        }
        try execute("BEGIN IMMEDIATE", values: [])
        isInTransaction = true
        do {
            let result = try body()
            try execute("COMMIT", values: [])
            isInTransaction = false
            return result
        } catch {
            isInTransaction = false
            try? execute("ROLLBACK", values: [])
            throw error
        }
    }

    private func selectJSON<T: Decodable>(_ sql: String, values: [SQLiteValue], as type: T.Type) throws -> [T] {
        guard !isUnavailable else {
            throw DatabaseError.databaseUnavailable
        }
        var statement: OpaquePointer?
        guard let database else {
            throw DatabaseError.databaseUnavailable
        }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer {
            sqlite3_finalize(statement)
        }
        try bind(values, to: statement)

        var output: [T] = []
        while true {
            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW || stepResult == SQLITE_DONE else {
                // A mid-loop error (corruption, I/O failure) must surface —
                // silently returning partial rows would masquerade as a
                // complete result set.
                throw DatabaseError.stepFailed(lastErrorMessage())
            }
            guard stepResult == SQLITE_ROW else {
                break
            }
            guard let textPointer = sqlite3_column_text(statement, 0) else {
                continue
            }
            let json = String(cString: textPointer)
            guard let data = json.data(using: .utf8) else {
                throw DatabaseError.decodingFailed(String(localized: "Stored JSON was not UTF-8.", comment: "Error when stored JSON cannot be decoded as UTF-8"))
            }
            do {
                output.append(try decoder.decode(T.self, from: data))
            } catch {
                throw DatabaseError.decodingFailed(error.localizedDescription)
            }
        }
        return output
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let bindIndex = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = sqlite3_bind_text(statement, bindIndex, string, -1, sqliteTransient)
            case .integer(let int):
                result = sqlite3_bind_int64(statement, bindIndex, int)
            case .real(let double):
                result = sqlite3_bind_double(statement, bindIndex, double)
            case .null:
                result = sqlite3_bind_null(statement, bindIndex)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bindFailed(lastErrorMessage())
            }
        }
    }

    private func lastErrorMessage() -> String {
        guard let database, let error = sqlite3_errmsg(database) else {
            return String(localized: "Unknown SQLite error.", comment: "Fallback error message for unknown SQLite error")
        }
        return String(cString: error)
    }
}
