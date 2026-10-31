import Foundation

public enum SafetyDecision: String, Codable, Sendable {
    case allowed
    case rejected
    case needsManualReview
}

public struct SafetyAuditResult: Codable, Sendable {
    public var decision: SafetyDecision
    public var reasons: [String]
    public var undoStatus: UndoStatus
    /// When the audit ran. Executors treat audits older than `auditFreshnessWindow`
    /// as stale and must re-audit before mutating.
    public var auditedAt: Date
}

/// Batch-wide execution limits that bound the blast radius of a single run.
public enum ExecutionLimits {
    public static let maxActionsPerBatch = 200
    public static let maxBytesPerBatch: Int64 = 50_000_000_000
    /// An audit older than this must be re-run before mutation.
    public static let auditFreshnessWindow: TimeInterval = 60
}

public enum SafetyAuditError: Error, LocalizedError, Sendable {
    case missingTarget(String)
    case identityMismatch(URL)
    case unapprovedAction
    case unsafePath(URL, Set<RiskFlag>)
    case symlinkTarget(URL)
    case cloudSideEffect(URL)
    case highRiskDestructiveAction(URL)
    case unsupportedAction(ActionType)
    /// Target existed at audit time but is gone by mutation time — nothing to act on.
    case targetVanished(URL)
    case unsafeDestination(URL)
    case staleAudit(URL)
    /// A cloneDeduplicate action names no keeper (destination), or the keeper
    /// is not among the scanned files.
    case missingKeeper(URL?)
    /// A cloneDeduplicate target and its keeper live on different volumes;
    /// APFS clones can never cross a volume boundary.
    case crossVolumeFold(URL)

    public var errorDescription: String? {
        switch self {
        case .missingTarget(let id):
            return String(localized: "Planned action references a missing target: \(id)", comment: "Safety audit missing target error")
        case .identityMismatch(let url):
            return String(localized: "File identity changed since scan: \(url.path)", comment: "Safety audit identity mismatch error")
        case .unapprovedAction:
            return String(localized: "The action has not been approved.", comment: "Safety audit unapproved action error")
        case .unsafePath(let url, let flags):
            let flagNames = flags.map(\.rawValue).joined(separator: ", ")
            return String(localized: "Unsafe path rejected: \(url.path) (\(flagNames))", comment: "Safety audit protected-path rejection")
        case .symlinkTarget(let url):
            return String(localized: "Destructive actions against symlinks are rejected: \(url.path)", comment: "Safety audit symlink rejection")
        case .cloudSideEffect(let url):
            return String(localized: "Cloud-synced local path rejected for Phase 1 deletion: \(url.path)", comment: "Safety audit cloud path rejection")
        case .highRiskDestructiveAction(let url):
            return String(localized: "High-risk destructive action rejected: \(url.path)", comment: "Safety audit high-risk rejection")
        case .unsupportedAction(let action):
            return String(localized: "This action type is not supported by the executor: \(action.rawValue)", comment: "Unsupported action type error")
        case .targetVanished(let url):
            return String(localized: "Target no longer exists on disk: \(url.path)", comment: "Target vanished before execution")
        case .unsafeDestination(let url):
            return String(localized: "Action destination is not safe: \(url.path)", comment: "Unsafe action destination error")
        case .staleAudit(let url):
            return String(localized: "Safety audit for \(url.path) is stale; re-audit before executing.", comment: "Stale audit error")
        case .missingKeeper(let url):
            if let url {
                return String(localized: "Clone action has no keeper file on record: \(url.path)", comment: "Missing clone keeper error")
            }
            return String(localized: "Clone action names no keeper file.", comment: "Missing clone keeper destination error")
        case .crossVolumeFold(let url):
            return String(localized: "Cannot fold \(url.path) onto a keeper on a different volume.", comment: "Cross-volume fold error")
        }
    }
}

public actor SafetyAuditor {
    private let policy: PathSafetyPolicy
    private let fileManager: FileManager

    public init(policy: PathSafetyPolicy = PathSafetyPolicy(), fileManager: FileManager = .default) {
        self.policy = policy
        self.fileManager = fileManager
    }

    public func audit(action: PlannedAction, filesByID: [String: FileRecord]) throws -> SafetyAuditResult {
        if action.actionType == .inspectOnly {
            return SafetyAuditResult(decision: .allowed, reasons: ["Inspection-only action."], undoStatus: .notUndoable, auditedAt: Date())
        }

        guard action.userDecision == .approved || action.userDecision == .alwaysDoThis else {
            throw SafetyAuditError.unapprovedAction
        }

        if action.actionType == .runProviderCleanup {
            // The executor has no implementation for provider cleanups (typed
            // unsupportedAction failure). Reject at audit time so approved
            // actions cannot silently fail later.
            throw SafetyAuditError.unsupportedAction(action.actionType)
        }

        if action.actionType == .runPackageManagerCleanup {
            // Audit only runs for user-approved actions (the executor pre-filters on
            // userDecision), so an explicit approval IS the required review for these
            // provider-CLI cleanups. Returning .needsManualReview here was a dead-end:
            // the executor converted it to a failure and the user never got a review
            // chance. The reason still warns that cleanup is not fully undoable.
            return SafetyAuditResult(
                decision: .allowed,
                reasons: ["Package-manager cleanup uses the provider CLI and is not fully undoable; explicit user approval serves as the required review."],
                undoStatus: .notUndoable,
                auditedAt: Date()
            )
        }

        // Destination validation: a safe file must not be moved/archived/aliased
        // into a protected, cloud-synced, or Trash location. For clone actions
        // the destination is the keeper FILE (not a directory) and is validated as one.
        if let destination = action.destination {
            let destinationIsDirectory = action.actionType != .cloneDeduplicate
            if case .deny = policy.decide(target: destination, isDirectory: destinationIsDirectory) {
                throw SafetyAuditError.unsafeDestination(destination)
            }
        }

        // Collect all target records; report all missing targets together instead of aborting on the first one.
        var records: [FileRecord] = []
        var missingTargets: [String] = []
        for targetID in action.targets {
            if let record = filesByID[targetID] {
                records.append(record)
            } else {
                missingTargets.append(targetID)
            }
        }
        if !missingTargets.isEmpty {
            throw SafetyAuditError.missingTarget(missingTargets.joined(separator: ", "))
        }

        var reasons: [String] = []
        var needsReview = false
        var keeperRecord: FileRecord?

        // Clone actions fold every target onto the keeper named by the
        // destination. The keeper must be a known scanned file whose identity
        // still matches; per-target volume checks run in the loop below.
        if action.actionType == .cloneDeduplicate {
            guard let keeperURL = action.destination else {
                throw SafetyAuditError.missingKeeper(nil)
            }
            guard let keeper = filesByID.values.first(where: { $0.url.path == keeperURL.path }) else {
                throw SafetyAuditError.missingKeeper(keeperURL)
            }
            switch checkIdentity(keeper) {
            case .vanished:
                throw SafetyAuditError.targetVanished(keeper.url)
            case .mismatch:
                throw SafetyAuditError.identityMismatch(keeper.url)
            case .missingFields:
                needsReview = true
                reasons.append("Identity fields missing for keeper \(keeper.displayPath); manual review required.")
            case .verified:
                reasons.append("Verified keeper \(keeper.displayPath)")
            }
            keeperRecord = keeper
        }

        for record in records {
            // APFS clones cannot cross a volume boundary; a stale plan whose
            // target moved volumes since the scan fails closed.
            if action.actionType == .cloneDeduplicate,
               let targetDevice = record.identity.deviceIdentifier,
               let keeperDevice = keeperRecord?.identity.deviceIdentifier,
               targetDevice != keeperDevice {
                throw SafetyAuditError.crossVolumeFold(record.url)
            }
            // Identity check runs first so a vanished target is skipped before any other check
            // can flag it for manual review. Outcomes:
            //  - .vanished:  the file no longer exists on disk. There is nothing to act on,
            //                so it is safe to skip this target and continue with the remaining
            //                (independently-verified) targets. The executor will record a
            //                per-target failure when it tries to act on the missing file.
            //  - .mismatch:  the file exists but its device/inode changed since scan — a TOCTOU
            //                swap. Abort the whole action (fail safe).
            //  - .missingFields / .verified: as before.
            switch checkIdentity(record) {
            case .vanished:
                reasons.append("Target \(record.displayPath) no longer exists on disk; it will be skipped and reported as a failure.")
                continue
            case .mismatch:
                throw SafetyAuditError.identityMismatch(record.url)
            case .missingFields:
                needsReview = true
                reasons.append("Identity fields missing for \(record.displayPath); manual review required.")
            case .verified:
                reasons.append("Verified \(record.displayPath)")
            }
            if requiresIntegrity(action.actionType) {
                if !fileManager.isReadableFile(atPath: record.url.path) {
                    reasons.append("App does not have read access to \(record.displayPath); manual review required.")
                    needsReview = true
                    // Do NOT continue — still run subsequent safety checks using file record metadata.
                    // A non-readable file could be a symlink to a protected path or a cloud-synced file.
                }
            }
            if requiresIntegrity(action.actionType), record.isSymlink {
                throw SafetyAuditError.symlinkTarget(record.url)
            }
            // Fresh symlink check: a regular file at scan time may have been replaced with a
            // symlink before execution. `destinationOfSymbolicLink` returns the target only when
            // the path is currently a symlink (it does not follow the link), giving us an lstat-
            // equivalent without relying on stale `record.isSymlink`. Reject to fail safe.
            if requiresIntegrity(action.actionType), (try? fileManager.destinationOfSymbolicLink(atPath: record.url.path)) != nil {
                throw SafetyAuditError.symlinkTarget(record.url)
            }
            if requiresIntegrity(action.actionType) {
                if case .deny = policy.decide(target: record.url, isDirectory: record.kind == .directory) {
                    throw SafetyAuditError.unsafePath(record.url, policy.riskFlags(for: record.url, isDirectory: record.kind == .directory))
                }
            }
            // `decide` already resolves symlinked ancestors internally; this
            // check only re-verifies the already-resolved path for defense in
            // depth (e.g. a swap between the two checks still fails closed).
            let resolvedParent = record.url.deletingLastPathComponent().resolvingSymlinksInPath()
            let resolvedURL = resolvedParent.appendingPathComponent(record.url.lastPathComponent)
            if requiresIntegrity(action.actionType), resolvedURL.path != record.url.path {
                if case .deny = policy.decide(target: resolvedURL, isDirectory: record.kind == .directory) {
                    throw SafetyAuditError.unsafePath(resolvedURL, policy.riskFlags(for: resolvedURL, isDirectory: record.kind == .directory))
                }
            }
            let freshFlags = policy.riskFlags(for: record.url, isDirectory: record.kind == .directory)
            if freshFlags != record.riskFlags {
                needsReview = true
                reasons.append("Risk flags changed for \(record.displayPath); re-derived at audit time.")
            }
            if isDestructive(action.actionType), freshFlags.contains(.reviewOnly) || record.riskFlags.contains(.reviewOnly) {
                throw SafetyAuditError.unsafePath(record.url, freshFlags)
            }
            if requiresIntegrity(action.actionType), record.cloudProvider != nil {
                throw SafetyAuditError.cloudSideEffect(record.url)
            }
            if isDestructive(action.actionType), action.risk >= .high {
                // High-risk destructive actions may execute after explicit user approval,
                // but only when the UI set the explicit confirmation flag. Without it the
                // audit still rejects, so ordinary approvals cannot unlock them. Protected
                // paths are rejected above and are never excused by approval or the flag.
                guard action.requiresExplicitConfirmation == true else {
                    throw SafetyAuditError.highRiskDestructiveAction(record.url)
                }
            }
        }

        return SafetyAuditResult(
            decision: needsReview ? .needsManualReview : .allowed,
            reasons: reasons,
            undoStatus: undoStatus(for: action.actionType),
            auditedAt: Date()
        )
    }

    /// Re-verify a target's identity IMMEDIATELY before the filesystem mutation.
    /// The audit-time check can go stale (user swaps the file between approval and
    /// execution); closing that gap requires checking again at mutation time.
    /// Throws `identityMismatch` on a swap (abort) and `targetVanished` when the
    /// file is simply gone (nothing to act on — caller reports a per-target failure).
    public func verifyTargetUnchanged(_ record: FileRecord) throws {
        switch checkIdentity(record) {
        case .verified:
            return
        case .vanished:
            throw SafetyAuditError.targetVanished(record.url)
        case .mismatch:
            throw SafetyAuditError.identityMismatch(record.url)
        case .missingFields:
            // Cannot prove identity at mutation time — fail safe rather than act unverified.
            throw SafetyAuditError.identityMismatch(record.url)
        }
    }

    /// Outcome of verifying a target file's identity at audit time.
    private enum IdentityCheck {
        /// File no longer exists on disk. Nothing to act on — safe to skip and report as a failure.
        case vanished
        /// File exists but device/inode changed since scan — a TOCTOU swap. Abort the action.
        case mismatch
        /// File exists but the scan record lacks identity fields — cannot verify, needs review.
        case missingFields
        /// File exists and identity matches the scan record.
        case verified
    }

    /// Verify a target file is the same one the user approved, without a TOCTOU gap.
    /// A file that has vanished from disk is reported as `.vanished` (safe to skip) rather than
    /// a mismatch, because there is nothing to act on; a file that exists but has a different
    /// device/inode is a true swap and is reported as `.mismatch` (abort, fail safe).
    /// An in-place rewrite (same inode, different size/mtime) is also a mismatch:
    /// device/inode-only identity would otherwise approve a file whose bytes changed.
    private func checkIdentity(_ record: FileRecord) -> IdentityCheck {
        // Single stat() call to avoid TOCTOU between existence check and attribute read.
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: record.url.path)
        } catch {
            // Distinguish "file no longer exists" (nothing to act on → safe to skip) from
            // "file exists but we cannot stat it" (e.g. permission denied → cannot verify
            // identity, needs manual review). Conflating the two would either skip a file
            // that is still present (unsafe) or abort the whole action for a vanished file
            // (overly conservative). NSFileNoSuchFileError == 4 in the Cocoa error domain.
            let nsError = error as NSError
            // `attributesOfItem` reports a missing file as NSFileReadNoSuchFileError (260);
            // NSFileNoSuchFileError (4) is the other variant. Treat both as "vanished".
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError {
                return .vanished
            }
            // File likely exists but is unreadable at the stat level: we cannot confirm
            // identity, so require manual review rather than skipping or aborting.
            return .missingFields
        }
        let currentDevice = (attributes[.systemNumber] as? NSNumber)?.uint64Value
        let currentInode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let hasDeviceID = record.identity.deviceIdentifier != nil
        let hasInodeID = record.identity.inodeIdentifier != nil

        // If the record has identity fields but stat returned nil for either, we cannot verify — treat as mismatch.
        if hasDeviceID && currentDevice == nil {
            return .mismatch
        }
        if hasInodeID && currentInode == nil {
            return .mismatch
        }
        if hasDeviceID, let expectedDevice = record.identity.deviceIdentifier,
           let currentDevice,
           expectedDevice != currentDevice {
            return .mismatch
        }
        if hasInodeID, let expectedInode = record.identity.inodeIdentifier,
           let currentInode,
           expectedInode != currentInode {
            return .mismatch
        }
        // In-place rewrite detection: same inode but different bytes. Size is
        // exact; mtime uses a 1s tolerance for filesystem timestamp granularity.
        if let expectedSize = record.identity.sizeBytes,
           let currentSize = (attributes[.size] as? NSNumber)?.int64Value,
           expectedSize != currentSize {
            return .mismatch
        }
        if let expectedMtime = record.identity.modifiedAt,
           let currentMtime = attributes[.modificationDate] as? Date,
           abs(currentMtime.timeIntervalSince(expectedMtime)) > 1 {
            return .mismatch
        }
        return hasDeviceID && hasInodeID ? .verified : .missingFields
    }

    private func isDestructive(_ actionType: ActionType) -> Bool {
        switch actionType {
        case .moveToTrash, .move, .rename, .archive:
            true
        case .restore, .tag, .offloadLocalCopy, .createAlias, .createSymlink, .runProviderCleanup, .runPackageManagerCleanup, .inspectOnly, .cloneDeduplicate, .unfoldClone:
            false
        }
    }

    /// Actions that rewrite a file in place and therefore demand the same
    /// integrity checks as destructive ones. `cloneDeduplicate` never deletes
    /// anything, but a fold swaps the file's inode — a cloud sync engine would
    /// re-upload the file as a change, and a symlink or protected-path swap
    /// must fail closed exactly like a destructive action. `.tag` writes an
    /// xattr, which follows symlinks and modifies the target file's metadata,
    /// so it demands the same checks.
    private func requiresIntegrity(_ actionType: ActionType) -> Bool {
        isDestructive(actionType) || actionType == .cloneDeduplicate || actionType == .tag
    }

    private func undoStatus(for actionType: ActionType) -> UndoStatus {
        switch actionType {
        case .moveToTrash, .move, .rename, .tag, .createAlias, .createSymlink, .archive, .cloneDeduplicate:
            .available
        case .restore:
            .available
        case .offloadLocalCopy, .runProviderCleanup, .runPackageManagerCleanup, .inspectOnly, .unfoldClone:
            .notUndoable
        }
    }
}
