import Foundation
import os

/// Abstraction over the platform Trash operation so the Core executor stays
/// free of AppKit. The AppKit layer provides the FileManager.trashItem
/// implementation; tests inject a recording double.
public protocol TrashService: Sendable {
    func trashItem(at url: URL) throws -> URL?
}

public struct ExecutionSummary: Sendable {
    public var logs: [OperationLog]
    public var undoRecords: [UndoRecord]
    public var failures: [String]
    /// Action IDs that had at least one failed target. Used to mark actions as `.failed` instead of `.completed`.
    public var failedActionIDs: Set<String>
    /// True when the safety auditor required manual review, so the caller can
    /// guide the user to refresh file identities with a new scan — without
    /// matching on localized failure strings.
    public var requiresRescan = false
}

public enum ActionExecutorError: Error, LocalizedError, Sendable {
    case missingDestination
    case missingTarget(String)
    case unsupportedAction(ActionType)
    case packageCandidateMissing(String)
    case processFailed(String)
    case manualReviewRequired(ActionType)
    /// The action already ran once (executedAt stamped); refusing to run it again.
    case alreadyExecuted(String)
    case batchLimitExceeded(String)
    case staleAudit(String)
    /// The undo trail could not be persisted ahead of the mutation, so the
    /// mutation was refused — deleting without a recoverable trail is never acceptable.
    case undoTrailUnavailable(String)
    /// A tool the command depends on is running (e.g. Simulator during simctl).
    case toolRunning(String)

    public var errorDescription: String? {
        switch self {
        case .missingDestination: String(localized: "The planned action is missing a destination.")
        case .missingTarget(let id): String(localized: "Missing target \(id).")
        case .unsupportedAction(let action): String(localized: "Unsupported action: \(action.rawValue)")
        case .packageCandidateMissing(let id): String(localized: "Missing package cleanup candidate: \(id).")
        case .processFailed(let message): message
        case .manualReviewRequired(let action): String(localized: "Manual review is still required before executing \(action.rawValue).")
        case .alreadyExecuted(let id): String(localized: "Action \(id) was already executed and cannot run again.")
        case .batchLimitExceeded(let reason): String(localized: "Batch limit exceeded: \(reason)")
        case .staleAudit(let reason): String(localized: "Stale safety audit: \(reason)")
        case .undoTrailUnavailable(let reason): String(localized: "Could not record the undo trail (\(reason)); the action was not performed.")
        case .toolRunning(let name): String(localized: "Quit \(name) first, then try again.")
        }
    }
}

public actor ActionExecutor {
    private let store: SQLiteStore
    private let auditor: SafetyAuditor
    private let fileManager: FileManager
    private let trash: TrashService
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "ActionExecutor")
    private let executorVersion = "1.0"
    private let commandTimeout: TimeInterval
    /// Set by cancelExecution(); checked between actions so long batches can
    /// stop after the current action instead of running everything.
    private var isCancelled = false

    public init(store: SQLiteStore, auditor: SafetyAuditor = SafetyAuditor(), fileManager: FileManager = .default, trash: TrashService? = nil, commandTimeout: TimeInterval = 600) {
        self.store = store
        self.auditor = auditor
        self.fileManager = fileManager
        self.trash = trash ?? FileSystemTrashProvider()
        self.commandTimeout = commandTimeout
    }

    /// Stop the in-flight batch after the currently executing action completes.
    public func cancelExecution() {
        isCancelled = true
    }

    public func execute(
        actions: [PlannedAction],
        filesByID: [String: FileRecord],
        packageCandidates: [PackageCleanupCandidate] = [],
        progress: (@Sendable (Int) async -> Void)? = nil
    ) async -> ExecutionSummary {
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var failures: [String] = []
        var failedActionIDs: Set<String> = []

        let executableActions = actions.filter { $0.userDecision == .approved || $0.userDecision == .alwaysDoThis }
        if executableActions.count > ExecutionLimits.maxActionsPerBatch {
            return ExecutionSummary(
                logs: [],
                undoRecords: [],
                failures: [ActionExecutorError.batchLimitExceeded("\(executableActions.count) approved actions exceeds the per-batch cap of \(ExecutionLimits.maxActionsPerBatch). Approve fewer actions at a time.").localizedDescription],
                failedActionIDs: Set(executableActions.map(\.id))
            )
        }
        let batchBytes = Set(executableActions.flatMap(\.targets)).compactMap { filesByID[$0]?.sizeBytes }.reduce(Int64(0), +)
        if batchBytes > ExecutionLimits.maxBytesPerBatch {
            return ExecutionSummary(
                logs: [],
                undoRecords: [],
                failures: [ActionExecutorError.batchLimitExceeded("Selected actions total \(batchBytes.formattedByteCount), over the per-batch cap of \(ExecutionLimits.maxBytesPerBatch.formattedByteCount).").localizedDescription],
                failedActionIDs: Set(executableActions.map(\.id))
            )
        }
        var completed = 0
        var requiresRescan = false
        isCancelled = false
        for action in executableActions {
            // Cancellation lands between actions: the in-flight action finishes
            // (its undo trail stays consistent), remaining ones never start.
            if isCancelled {
                failures.append(String(localized: "Execution cancelled; remaining actions were not run."))
                break
            }
            do {
                // Idempotency guard: a stamped action (already executed once) must
                // never run again — double-click, retry after timeout, or a stale
                // persisted plan would otherwise trash the regenerated files.
                if action.executedAt != nil {
                    throw ActionExecutorError.alreadyExecuted(action.id)
                }
                let audit = try await auditor.audit(action: action, filesByID: filesByID)
                guard audit.decision == .allowed else {
                    throw ActionExecutorError.manualReviewRequired(action.actionType)
                }
                guard Date().timeIntervalSince(audit.auditedAt) <= ExecutionLimits.auditFreshnessWindow else {
                    throw ActionExecutorError.staleAudit("Re-approve \(action.id). Its safety audit expired.")
                }
                let result = try await execute(action: action, filesByID: filesByID, packageCandidates: packageCandidates)
                // Persist undo records and operation logs immediately after each action.
                // If persistence fails, log the failure but do NOT abort — the disk operation
                // already succeeded, and the in-memory summary still carries the records for
                // the current session. The next app restart will lose them, but at least the
                // user can undo within this session.
                var persistFailed = false
                for undo in result.undoRecords {
                    do {
                        try await store.saveUndoRecord(undo)
                    } catch {
                        logger.error("Failed to persist undo record: \(error.localizedDescription, privacy: .public)")
                        persistFailed = true
                    }
                }
                for log in result.logs {
                    do {
                        try await store.saveOperationLog(log)
                    } catch {
                        logger.error("Failed to persist operation log: \(error.localizedDescription, privacy: .public)")
                        persistFailed = true
                    }
                }
                logs.append(contentsOf: result.logs)
                undoRecords.append(contentsOf: result.undoRecords)
                failedActionIDs.formUnion(result.failedActionIDs)
                if persistFailed {
                    failures.append(String(
                        localized: "Undo records may not persist across app restart.",
                        comment: "Execution summary note when the undo trail could not be written"))
                }
                if !result.failures.isEmpty {
                    failedActionIDs.insert(action.id)
                    failures.append(contentsOf: result.failures)
                }
            } catch {
                logger.error("Action failed: \(error.localizedDescription, privacy: .public)")
                if case ActionExecutorError.manualReviewRequired = error {
                    requiresRescan = true
                }
                failedActionIDs.insert(action.id)
                failures.append(error.localizedDescription)
            }
            completed += 1
            await progress?(completed)
        }

        return ExecutionSummary(
            logs: logs, undoRecords: undoRecords, failures: failures,
            failedActionIDs: failedActionIDs, requiresRescan: requiresRescan)
    }

    private func execute(
        action: PlannedAction,
        filesByID: [String: FileRecord],
        packageCandidates: [PackageCleanupCandidate]
    ) async throws -> ExecutionSummary {
        switch action.actionType {
        case .moveToTrash:
            return await moveToTrash(action: action, filesByID: filesByID)
        case .move:
            return try await move(action: action, filesByID: filesByID)
        case .tag:
            return await tag(action: action, filesByID: filesByID)
        case .createAlias:
            return await createAlias(action: action, filesByID: filesByID)
        case .createSymlink:
            return await createSymlink(action: action, filesByID: filesByID)
        case .archive:
            return try await archive(action: action, filesByID: filesByID)
        case .runPackageManagerCleanup:
            return try await runPackageCleanup(action: action, packageCandidates: packageCandidates)
        case .rename:
            return try await rename(action: action, filesByID: filesByID)
        case .cloneDeduplicate:
            return await cloneDeduplicate(action: action, filesByID: filesByID)
        case .offloadLocalCopy, .runProviderCleanup, .inspectOnly, .restore, .unfoldClone:
            // These action types have no real implementation. Persisted plans may still
            // contain them, so degrade to a typed failure instead of pretending success
            // or touching the filesystem.
            throw ActionExecutorError.unsupportedAction(action.actionType)
        }
    }

    private func moveToTrash(action: PlannedAction, filesByID: [String: FileRecord]) async -> ExecutionSummary {
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                continue
            }
            // Write-ahead undo trail: persist a PENDING log+record BEFORE touching
            // the filesystem. A crash between trashItem() and the finalize update
            // leaves a recoverable trail (startup sweep surfaces the original path)
            // instead of an untracked file silently sitting in the Trash.
            let validUntil = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .moveToTrash,
                before: ["path": record.displayPath, "file_id": record.id],
                after: [:],
                result: "moving_to_trash",
                inverse: .restore,
                restoreURL: record.url,
                trashURL: nil,
                validUntil: validUntil,
                undoStatus: .pending
            )
            do {
                // Write-ahead persistence first: refuse the mutation when the
                // trail cannot be recorded (deleting without a recoverable
                // trail is never acceptable).
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            do {
                // TOCTOU closure: re-verify identity NOW, with nothing but the
                // unavoidable syscall gap between this check and trashItem.
                try await auditor.verifyTargetUnchanged(record)
                let trashURL = try trash.trashItem(at: record.url)
                // Finalize the trail with the real outcome: trash location plus the
                // captured identity restore later verifies against.
                var finalizedLog = log
                finalizedLog.result = "moved_to_trash"
                finalizedLog.afterState = ["trash_path": trashURL?.path ?? ""]
                if let trashURL {
                    finalizedLog.afterState["trash_identity"] = FileArtifactIdentity.capture(at: trashURL)?.encodedString
                }
                var finalizedUndo = undo
                finalizedUndo.trashURL = trashURL
                finalizedUndo.status = .available
                try await store.saveOperationLog(finalizedLog)
                try await store.saveUndoRecord(finalizedUndo)
                logs.append(finalizedLog)
                undoRecords.append(finalizedUndo)
            } catch {
                // The trash failed — downgrade the pending trail so the startup
                // sweep does not report a phantom interrupted operation forever.
                await downgradePendingTrail(undo)
                errors.append(error.localizedDescription)
            }
        }
        return ExecutionSummary(logs: logs, undoRecords: undoRecords, failures: errors, failedActionIDs: [])
    }

    /// Folds each approved duplicate onto its keeper as an APFS clone: the
    /// duplicate's path, contents and metadata stay exactly as they were, but
    /// it stops paying for its own storage blocks. Nothing is deleted, so undo
    /// never expires. Mirrors the moveToTrash write-ahead pattern: the PENDING
    /// undo trail is persisted BEFORE the filesystem mutation, so a crash
    /// mid-fold still leaves a recoverable record (undo re-splits the clone
    /// into a real private copy).
    private func cloneDeduplicate(action: PlannedAction, filesByID: [String: FileRecord]) async -> ExecutionSummary {
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        var hadFailure = false

        guard let keeperURL = action.destination else {
            return ExecutionSummary(
                logs: [],
                undoRecords: [],
                failures: [ActionExecutorError.missingDestination.localizedDescription],
                failedActionIDs: [action.id]
            )
        }
        guard let keeper = filesByID.values.first(where: { $0.url.path == keeperURL.path }) else {
            return ExecutionSummary(
                logs: [],
                undoRecords: [],
                failures: [SafetyAuditError.missingKeeper(keeperURL).localizedDescription],
                failedActionIDs: [action.id]
            )
        }

        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                hadFailure = true
                continue
            }
            // Write-ahead undo trail: persist a PENDING log+record BEFORE the
            // fold replaces the file's inode. trashURL carries the keeper for
            // context; restoreURL is the folded file itself.
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .cloneDeduplicate,
                before: ["path": record.displayPath, "file_id": record.id],
                after: [:],
                result: "folding_into_clone",
                inverse: .unfoldClone,
                restoreURL: record.url,
                trashURL: keeper.url,
                validUntil: nil,
                undoStatus: .pending
            )
            do {
                // Write-ahead persistence first (same contract as moveToTrash).
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                hadFailure = true
                continue
            }
            do {
                // TOCTOU closure: re-verify identity NOW on both files, right
                // before the fold replaces the duplicate's inode.
                try await auditor.verifyTargetUnchanged(record)
                try await auditor.verifyTargetUnchanged(keeper)
            } catch {
                await downgradePendingTrail(undo)
                errors.append(error.localizedDescription)
                hadFailure = true
                continue
            }

            switch APFSCloneService.fold(duplicate: record.url, keeper: keeper.url) {
            case .folded(let freedBytes):
                var finalizedLog = log
                finalizedLog.result = "folded_into_clone"
                finalizedLog.afterState = [
                    "keeper_path": keeper.displayPath,
                    "freed_bytes": String(freedBytes)
                ]
                // Capture the NEW identity (the fold creates a fresh inode);
                // undo verifies against it before writing a private copy back.
                if let identity = FileArtifactIdentity.capture(at: record.url) {
                    finalizedLog.afterState["clone_identity"] = identity.encodedString
                }
                var finalizedUndo = undo
                finalizedUndo.status = .available
                try? await store.saveOperationLog(finalizedLog)
                try? await store.saveUndoRecord(finalizedUndo)
                logs.append(finalizedLog)
                undoRecords.append(finalizedUndo)
            case .alreadyShared:
                // Both paths already share storage (hard link, earlier fold):
                // nothing to do and nothing wrong. Keep the info log, drop the
                // pending undo so the startup sweep never reports it.
                var infoLog = log
                infoLog.result = "already_shared"
                try? await store.saveOperationLog(infoLog)
                var droppedUndo = undo
                droppedUndo.status = .failed
                try? await store.saveUndoRecord(droppedUndo)
                logs.append(infoLog)
            case .skipped(let reason), .changed(let reason), .failed(let reason):
                var failedUndo = undo
                failedUndo.status = .failed
                try? await store.saveUndoRecord(failedUndo)
                errors.append("\(record.displayPath): \(reason)")
                hadFailure = true
            }
        }
        return ExecutionSummary(
            logs: logs,
            undoRecords: undoRecords,
            failures: errors,
            failedActionIDs: hadFailure ? [action.id] : []
        )
    }

    private func move(action: PlannedAction, filesByID: [String: FileRecord]) async throws -> ExecutionSummary {
        guard let destination = action.destination else {
            throw ActionExecutorError.missingDestination
        }
        try validatedDestination(destination)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                continue
            }
            // Write-ahead undo trail: persist a PENDING log+record BEFORE
            // moving the file. A crash between moveItem and the finalize
            // update leaves a recoverable trail (the startup sweep surfaces
            // the original path) instead of a silently moved file.
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .move,
                before: ["path": record.displayPath],
                after: [:],
                result: "moving",
                inverse: .move,
                restoreURL: record.url,
                trashURL: nil,
                undoStatus: .pending
            )
            do {
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            do {
                // TOCTOU closure: re-verify identity immediately before mutating.
                try await auditor.verifyTargetUnchanged(record)
                let newURL = try moveItem(from: record, to: destination)
                var afterState: [String: String] = ["path": newURL.path]
                if let identity = FileArtifactIdentity.capture(at: newURL) {
                    afterState["moved_identity"] = identity.encodedString
                }
                var finalizedLog = log
                finalizedLog.result = "moved"
                finalizedLog.afterState = afterState
                var finalizedUndo = undo
                finalizedUndo.trashURL = newURL
                finalizedUndo.status = .available
                logs.append(finalizedLog)
                undoRecords.append(finalizedUndo)
                // The mutation succeeded; a failed finalize write keeps the
                // PENDING record (the sweep surfaces it) but is not an error.
                try? await store.saveOperationLog(finalizedLog)
                try? await store.saveUndoRecord(finalizedUndo)
            } catch {
                await downgradePendingTrail(undo)
                errors.append(error.localizedDescription)
            }
        }
        return ExecutionSummary(logs: logs, undoRecords: undoRecords, failures: errors, failedActionIDs: [])
    }

    private func tag(action: PlannedAction, filesByID: [String: FileRecord]) async -> ExecutionSummary {
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                continue
            }
            // Write-ahead undo trail: the pending log carries the tag states
            // only at finalize time, so persist the shell first and fill it in
            // after the xattr write succeeds.
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .tag,
                before: ["tags": ""],
                after: [:],
                result: "tagging",
                inverse: .tag,
                restoreURL: record.url,
                undoStatus: .pending
            )
            do {
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            do {
                try await auditor.verifyTargetUnchanged(record)
                // Read live tags from a fresh URL: the crawl does not record them, and
                // resource values cached on record.url would go stale after the write.
                let oldTags = (try? URL(fileURLWithPath: record.url.path).resourceValues(forKeys: [.tagNamesKey]))?
                    .tagNames ?? []
                var newTags = Set(oldTags)
                let tagName = taxonomyTagName(for: record, risk: action.risk)
                newTags.insert(tagName)
                let sortedTags = Array(newTags).sorted()
                try FinderTagHelper.write(sortedTags, to: record.url)
                var finalizedLog = log
                finalizedLog.beforeState = ["tags": oldTags.joined(separator: ",")]
                finalizedLog.afterState = ["tags": sortedTags.joined(separator: ",")]
                finalizedLog.result = "tagged"
                var finalizedUndo = undo
                finalizedUndo.status = .available
                logs.append(finalizedLog)
                undoRecords.append(finalizedUndo)
                try? await store.saveOperationLog(finalizedLog)
                try? await store.saveUndoRecord(finalizedUndo)
            } catch {
                await downgradePendingTrail(undo)
                // Per-target failure: keep tagging the remaining valid targets
                // instead of aborting the whole action (matches moveToTrash).
                errors.append(error.localizedDescription)
            }
        }
        return ExecutionSummary(logs: logs, undoRecords: undoRecords, failures: errors, failedActionIDs: [])
    }

    private func taxonomyTagName(for record: FileRecord, risk: RiskLevel) -> String {
        let ext = record.fileExtension?.lowercased() ?? ""
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "raw", "cr2", "nef", "arw", "dng"]
        let docExtensions: Set<String> = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx"]
        let exportExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "zip", "tar", "gz"]

        if imageExtensions.contains(ext) {
            return "Raw Photo"
        }
        if docExtensions.contains(ext) {
            return "Keep"
        }
        if exportExtensions.contains(ext) {
            return "Generated Export"
        }
        if risk == .low {
            return "Archive Candidate"
        }
        return "Review Later"
    }

    private func createAlias(action: PlannedAction, filesByID: [String: FileRecord]) async -> ExecutionSummary {
        let destination: URL
        do {
            destination = try preparedOrganizationDestination(action.destination, folderName: AppIdentity.aliasesFolderName)
        } catch {
            return ExecutionSummary(logs: [], undoRecords: [], failures: [error.localizedDescription], failedActionIDs: [])
        }
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                continue
            }
            // Collision-free alias name: two same-named targets in one batch
            // must not silently overwrite each other's artifacts.
            let aliasURL = collisionFreeArtifactURL(for: record.fileName, suffix: ".alias", in: destination)
            // Write-ahead undo trail: persist a PENDING log+record BEFORE the
            // bookmark write so a crash leaves a recoverable trail.
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .createAlias,
                before: ["path": record.displayPath],
                after: [:],
                result: "creating_alias",
                inverse: .moveToTrash,
                restoreURL: aliasURL,
                undoStatus: .pending
            )
            do {
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            do {
                try await auditor.verifyTargetUnchanged(record)
                let data = try record.url.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(data, to: aliasURL)
                var afterState: [String: String] = ["alias_path": aliasURL.path]
                if let identity = FileArtifactIdentity.capture(at: aliasURL) {
                    afterState["artifact_identity"] = identity.encodedString
                }
                var finalizedLog = log
                finalizedLog.result = "alias_created"
                finalizedLog.afterState = afterState
                var finalizedUndo = undo
                finalizedUndo.status = .available
                logs.append(finalizedLog)
                undoRecords.append(finalizedUndo)
                try? await store.saveOperationLog(finalizedLog)
                try? await store.saveUndoRecord(finalizedUndo)
            } catch {
                await downgradePendingTrail(undo)
                // Per-target failure: keep creating aliases for the remaining
                // valid targets instead of aborting the whole action.
                errors.append(error.localizedDescription)
            }
        }
        return ExecutionSummary(logs: logs, undoRecords: undoRecords, failures: errors, failedActionIDs: errors.isEmpty ? [] : [action.id])
    }

    private func createSymlink(action: PlannedAction, filesByID: [String: FileRecord]) async -> ExecutionSummary {
        let destination: URL
        do {
            destination = try preparedOrganizationDestination(action.destination, folderName: AppIdentity.linksFolderName)
        } catch {
            return ExecutionSummary(logs: [], undoRecords: [], failures: [error.localizedDescription], failedActionIDs: [])
        }
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                continue
            }
            let linkURL = collisionFreeArtifactURL(for: record.fileName, suffix: "", in: destination)
            // Write-ahead undo trail: persist a PENDING log+record BEFORE the
            // link creation so a crash leaves a recoverable trail.
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .createSymlink,
                before: ["path": record.displayPath],
                after: [:],
                result: "creating_symlink",
                inverse: .moveToTrash,
                restoreURL: linkURL,
                undoStatus: .pending
            )
            do {
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            do {
                try await auditor.verifyTargetUnchanged(record)
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: record.url)
                var afterState: [String: String] = ["link_path": linkURL.path]
                if let identity = FileArtifactIdentity.capture(at: linkURL) {
                    afterState["artifact_identity"] = identity.encodedString
                }
                var finalizedLog = log
                finalizedLog.result = "symlink_created"
                finalizedLog.afterState = afterState
                var finalizedUndo = undo
                finalizedUndo.status = .available
                logs.append(finalizedLog)
                undoRecords.append(finalizedUndo)
                try? await store.saveOperationLog(finalizedLog)
                try? await store.saveUndoRecord(finalizedUndo)
            } catch {
                await downgradePendingTrail(undo)
                // Per-target failure: keep creating links for the remaining
                // valid targets instead of aborting the whole action.
                errors.append(error.localizedDescription)
            }
        }
        return ExecutionSummary(logs: logs, undoRecords: undoRecords, failures: errors, failedActionIDs: errors.isEmpty ? [] : [action.id])
    }

    private func archive(action: PlannedAction, filesByID: [String: FileRecord]) async throws -> ExecutionSummary {
        let destination = try preparedOrganizationDestination(action.destination, folderName: AppIdentity.archiveFolderName)
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                continue
            }
            // UUID fragment prevents same-second same-name archives from overwriting
            // each other (the previous epoch-seconds suffix collided).
            let archiveName = record.fileName + "-" + String(Int(Date().timeIntervalSince1970)) + "-" + UUID().uuidString.prefix(8) + ".zip"
            let archiveURL = destination.appendingPathComponent(archiveName, isDirectory: false)
            // Write-ahead undo trail: the original is about to enter the Trash
            // with a 30-day clock, so the pending record must be durable BEFORE
            // any mutation — a crash mid-archive must still surface the
            // original's path via the startup sweep.
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .archive,
                before: ["path": record.displayPath, "file_id": record.id],
                after: [:],
                result: "archiving",
                inverse: .restore,
                restoreURL: record.url,
                trashURL: nil,
                validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                undoStatus: .pending
            )
            do {
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            /// Downgrades the pending trail after a failed archive step so the
            /// startup sweep never reports a phantom interrupted operation.
            func downgradePendingToFailed() async {
                var failedUndo = undo
                failedUndo.status = .failed
                try? await store.saveUndoRecord(failedUndo)
            }
            do {
                // TOCTOU closure: re-verify identity immediately before mutating.
                try await auditor.verifyTargetUnchanged(record)
            } catch {
                await downgradePendingTrail(undo)
                errors.append(error.localizedDescription)
                continue
            }
            let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-c", "-k", "--keepParent", record.url.path, archiveURL.path], timeout: commandTimeout)
            guard result.exitCode == 0 else {
                // ditto failed — clean up any partial archive so we never leave a corrupt ZIP
                // that the user might mistake for a valid backup of their original file.
                if fileManager.fileExists(atPath: archiveURL.path) {
                    try? fileManager.removeItem(at: archiveURL)
                }
                await await downgradePendingTrail(undo)
                errors.append(ActionExecutorError.processFailed(result.stderr).localizedDescription)
                continue
            }
            var trashURL: URL?
            do {
                // The archive step can take a while; re-verify identity again
                // immediately before the destructive trash.
                try await auditor.verifyTargetUnchanged(record)
                trashURL = try trash.trashItem(at: record.url)
            } catch {
                // Trash failed but the archive already exists — remove it so we
                // don't leave a duplicate copy of a file that is still in place.
                do {
                    try fileManager.removeItem(at: archiveURL)
                } catch {
                    logger.warning("Failed to clean up orphan archive \(archiveURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                await downgradePendingTrail(undo)
                errors.append(error.localizedDescription)
                continue
            }
            // Original is gone (trashed); only the archive remains, so its
            // orphan cleanup on trash failure no longer applies here.
            var afterState: [String: String] = ["archive_path": archiveURL.path, "trash_path": trashURL?.path ?? ""]
            if let identity = FileArtifactIdentity.capture(at: archiveURL) {
                afterState["artifact_identity"] = identity.encodedString
            }
            if let trashURL {
                afterState["trash_identity"] = FileArtifactIdentity.capture(at: trashURL)?.encodedString
            }
            var finalizedLog = log
            finalizedLog.result = "archived_and_moved_original_to_trash"
            finalizedLog.afterState = afterState
            var finalizedUndo = undo
            finalizedUndo.trashURL = trashURL
            finalizedUndo.status = trashURL == nil ? .failed : .available
            logs.append(finalizedLog)
            undoRecords.append(finalizedUndo)
            try? await store.saveOperationLog(finalizedLog)
            try? await store.saveUndoRecord(finalizedUndo)
            // Second undo record: trash the archive itself.
            let archiveTrashUndo = UndoRecord(
                id: UUID().uuidString,
                operationLogID: log.id,
                inverseAction: .moveToTrash,
                restoreURL: archiveURL,
                trashURL: nil,
                validUntil: nil,
                status: .available
            )
            undoRecords.append(archiveTrashUndo)
            try? await store.saveUndoRecord(archiveTrashUndo)
        }
        return ExecutionSummary(logs: logs, undoRecords: undoRecords, failures: errors, failedActionIDs: [])
    }

    /// First process name with a running instance (`pgrep -x`), if any.
    static func firstRunning(_ names: [String]) async -> String? {
        for name in names {
            let result = await ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/pgrep"), arguments: ["-x", name], timeout: 5)
            if result.exitCode == 0 { return name }
        }
        return nil
    }

    private func runPackageCleanup(action: PlannedAction, packageCandidates: [PackageCleanupCandidate]) async throws -> ExecutionSummary {
        var logs: [OperationLog] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let candidate = packageCandidates.first(where: { $0.id == targetID }) else {
                errors.append(ActionExecutorError.packageCandidateMissing(targetID).localizedDescription)
                continue
            }
            if let running = await Self.firstRunning(candidate.blockingProcesses ?? []) {
                errors.append(ActionExecutorError.toolRunning(running).localizedDescription)
                continue
            }
            let arguments = candidate.arguments
            let result = await ProcessRunner.run(candidate.commandPath, arguments: arguments, timeout: commandTimeout)
            guard result.exitCode == 0 else {
                errors.append(ActionExecutorError.processFailed(result.stderr).localizedDescription)
                continue
            }
            logs.append(OperationLog(
                id: UUID().uuidString,
                plannedActionID: action.id,
                operationType: .runPackageManagerCleanup,
                beforeState: ["command": ([candidate.commandPath.path] + candidate.arguments).joined(separator: " ")],
                afterState: ["output": result.stdout],
                executorVersion: executorVersion,
                result: "command_completed",
                error: nil,
                timestamp: Date()
            ))
        }
        return ExecutionSummary(logs: logs, undoRecords: [], failures: errors, failedActionIDs: [])
    }

    private func makeLogAndUndo(
        action: PlannedAction,
        type: ActionType,
        before: [String: String],
        after: [String: String],
        result: String,
        inverse: ActionType,
        restoreURL: URL?,
        trashURL: URL? = nil,
        validUntil: Date? = nil,
        undoStatus: UndoStatus = .available
    ) -> (OperationLog, UndoRecord) {
        let logID = UUID().uuidString
        let log = OperationLog(
            id: logID,
            plannedActionID: action.id,
            operationType: type,
            beforeState: before,
            afterState: after,
            executorVersion: executorVersion,
            result: result,
            error: nil,
            timestamp: Date()
        )
        let undo = UndoRecord(
            id: UUID().uuidString,
            operationLogID: logID,
            inverseAction: inverse,
            restoreURL: restoreURL,
            trashURL: trashURL,
            validUntil: validUntil,
            status: undoStatus
        )
        return (log, undo)
    }

    /// Write-ahead step shared by every mutating action: persist the PENDING
    /// log+undo BEFORE the filesystem mutation. Throws `undoTrailUnavailable`
    /// when persistence fails — the caller must then refuse the mutation.
    private func persistPendingTrail(_ log: OperationLog, _ undo: UndoRecord) async throws {
        do {
            try await store.saveOperationLog(log)
            try await store.saveUndoRecord(undo)
        } catch {
            throw ActionExecutorError.undoTrailUnavailable(error.localizedDescription)
        }
    }

    /// Downgrades a pending trail after a failed step so the startup sweep
    /// never reports a phantom interrupted operation.
    private func downgradePendingTrail(_ undo: UndoRecord) async {
        var failedUndo = undo
        failedUndo.status = .failed
        try? await store.saveUndoRecord(failedUndo)
    }

    private func preparedOrganizationDestination(_ destination: URL?, folderName: String) throws -> URL {
        let resolved = destination ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(folderName, isDirectory: true)
        try validatedDestination(resolved)
        try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        return resolved
    }

    /// Reject destinations the policy forbids (protected, cloud-synced, Trash).
    /// An existing symlinked destination is judged by where it points: a leaf
    /// symlink into a protected area must not become a move/rename target.
    private func validatedDestination(_ destination: URL) throws {
        let resolved = destination.resolvingSymlinksInPath()
        if case .deny = PathSafetyPolicy().decide(target: resolved, isDirectory: true) {
            throw SafetyAuditError.unsafeDestination(destination)
        }
    }

    private func rename(action: PlannedAction, filesByID: [String: FileRecord]) async throws -> ExecutionSummary {
        guard let destination = action.destination else {
            throw ActionExecutorError.missingDestination
        }
        try validatedDestination(destination)
        var logs: [OperationLog] = []
        var undoRecords: [UndoRecord] = []
        var errors: [String] = []
        for targetID in action.targets {
            guard let record = filesByID[targetID] else {
                errors.append(ActionExecutorError.missingTarget(targetID).localizedDescription)
                continue
            }
            // Write-ahead undo trail: persist a PENDING log+record BEFORE
            // renaming the file (same contract as .move).
            let (log, undo) = makeLogAndUndo(
                action: action,
                type: .rename,
                before: ["path": record.displayPath],
                after: [:],
                result: "renaming",
                inverse: .rename,
                restoreURL: record.url,
                trashURL: nil,
                undoStatus: .pending
            )
            do {
                try await persistPendingTrail(log, undo)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            do {
                // TOCTOU closure: re-verify identity immediately before mutating.
                try await auditor.verifyTargetUnchanged(record)
                let newURL = try moveItem(from: record, to: destination)
                var afterState: [String: String] = ["path": newURL.path]
                if let identity = FileArtifactIdentity.capture(at: newURL) {
                    afterState["moved_identity"] = identity.encodedString
                }
                var finalizedLog = log
                finalizedLog.result = "renamed"
                finalizedLog.afterState = afterState
                var finalizedUndo = undo
                finalizedUndo.trashURL = newURL
                finalizedUndo.status = .available
                logs.append(finalizedLog)
                undoRecords.append(finalizedUndo)
                try? await store.saveOperationLog(finalizedLog)
                try? await store.saveUndoRecord(finalizedUndo)
            } catch {
                var failedUndo = undo
                failedUndo.status = .failed
                try? await store.saveUndoRecord(failedUndo)
                errors.append(error.localizedDescription)
            }
        }
        return ExecutionSummary(logs: logs, undoRecords: undoRecords, failures: errors, failedActionIDs: [])
    }

    /// Collision-free artifact path inside `destination`: appends a numeric
    /// suffix when the name is taken so two same-named targets in one batch
    /// cannot silently overwrite each other's alias or symlink.
    private func collisionFreeArtifactURL(for fileName: String, suffix: String, in destination: URL) -> URL {
        var candidate = destination.appendingPathComponent(fileName + suffix, isDirectory: false)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }
        let nsName = fileName as NSString
        let baseName = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        var counter = 1
        repeat {
            let name = ext.isEmpty ? "\(baseName)-\(counter)\(suffix)" : "\(baseName)-\(counter).\(ext)\(suffix)"
            candidate = destination.appendingPathComponent(name, isDirectory: false)
            counter += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    /// Shared relocation helper for `.move` and `.rename`. Resolves a
    /// collision-free destination URL for `record` inside `destination`
    /// (appending a numeric suffix when the name is taken), then moves the
    /// item there. Identity capture and undo-record creation stay in the
    /// caller so each action keeps its own `OperationLog`/`UndoRecord` shape.
    private func moveItem(from record: FileRecord, to destination: URL) throws -> URL {
        var newURL = destination.appendingPathComponent(record.fileName, isDirectory: record.kind == .directory)
        if fileManager.fileExists(atPath: newURL.path) {
            let ext = record.url.pathExtension
            let baseName = record.url.deletingPathExtension().lastPathComponent
            var counter = 1
            repeat {
                let suffix = ext.isEmpty ? "" : ".\(ext)"
                newURL = destination.appendingPathComponent("\(baseName)-\(counter)\(suffix)", isDirectory: record.kind == .directory)
                counter += 1
            } while fileManager.fileExists(atPath: newURL.path)
        }
        try fileManager.moveItem(at: record.url, to: newURL)
        return newURL
    }
}
