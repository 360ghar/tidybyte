import Foundation
import MacOSCleanerCore

/// Tool errors surfaced to the agent as `isError` text results.
enum MCPError: Error, LocalizedError {
    case noScan
    case unknownTool(String)
    case unknownFinding(String)
    case unknownAction(String)
    case nothingToUndo(String)
    /// High-risk destructive actions never execute through MCP — the user
    /// must run those in the app where the explicit-confirmation flow lives.
    case highRiskRequiresApp

    var errorDescription: String? {
        switch self {
        case .noScan:
            "No scan yet. Call scan first."
        case .unknownTool(let name):
            "Unknown tool: \(name)."
        case .unknownFinding(let id):
            "No finding with id \(id) in the last scan."
        case .unknownAction(let id):
            "No pending action with id \(id) in the last plan."
        case .nothingToUndo(let id):
            "No undoable record for operation \(id)."
        case .highRiskRequiresApp:
            "This action is high risk and destructive; it can only be approved in the"
                + " Tidybyte app, never through MCP."
        }
    }
}

/// The MCP server brain: JSON-RPC request → response dictionaries. Deliberately
/// transport-agnostic (stdio lives in main.swift) so unit tests can drive
/// `handle(request:)` directly. Not an actor: the stdio loop processes one
/// request at a time on a single task, and every service it touches is an actor.
public final class MCPKit {
    static let serverName = AppIdentity.mcpServerName
    static let serverVersion = "1.0"
    static let defaultProtocolVersion = "2025-06-18"

    struct ScanState {
        let outcome: ScanOutcome
        let plan: Plan
        let filesByID: [String: FileRecord]
    }

    private let store: SQLiteStore
    private let orchestrator: ScanOrchestrator
    private let planner = PlannerAgent()
    private let executor: ActionExecutor
    private let undoService: UndoManagerService
    private var lastScan: ScanState?

    public init(store: SQLiteStore) {
        self.store = store
        let memory = MemoryEngine(store: store)
        self.orchestrator = ScanOrchestrator(store: store, memory: memory)
        self.executor = ActionExecutor(store: store)
        self.undoService = UndoManagerService(store: store, memory: memory)
    }

    // MARK: - JSON-RPC dispatch

    /// Handles one decoded JSON-RPC request. Returns nil for notifications
    /// (requests without an id get no response, per the MCP transport rules).
    public func handle(request: [String: Any]) async -> [String: Any]? {
        guard let method = request["method"] as? String else {
            return Self.errorPayload(id: request["id"] as Any, code: -32600, message: "Invalid Request")
        }
        guard let id = request["id"] else { return nil }
        switch method {
        case "initialize":
            let params = request["params"] as? [String: Any]
            let version = params?["protocolVersion"] as? String ?? Self.defaultProtocolVersion
            return Self.responsePayload(id: id, result: [
                "protocolVersion": version,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": Self.serverName, "version": Self.serverVersion],
                "instructions": """
                Local Mac cleanup agent. A human approves every change: always call execute without \
                confirm first, show the plan, and only call execute with confirm: true after the user \
                agrees. The fold action (cloneDeduplicate) deletes nothing; trash actions keep files \
                recoverable in Trash.
                """
            ])
        case "ping":
            return Self.responsePayload(id: id, result: [:])
        case "tools/list":
            return Self.responsePayload(id: id, result: ["tools": Self.toolDescriptions])
        case "tools/call":
            let params = request["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await callTool(name: name, arguments: arguments)
                return Self.responsePayload(id: id, result: [
                    "content": [["type": "text", "text": text]],
                    "isError": false
                ])
            } catch {
                return Self.responsePayload(id: id, result: [
                    "content": [["type": "text", "text": error.localizedDescription]],
                    "isError": true
                ])
            }
        default:
            return Self.errorPayload(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Tools

    private func callTool(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "scan": return try await toolScan(arguments)
        case "list_findings": return try toolListFindings(arguments)
        case "show_plan": return try toolShowPlan(arguments)
        case "check_finding": return try await toolCheckFinding(arguments)
        case "execute": return try await toolExecute(arguments)
        case "history": return try await toolHistory()
        case "undo": return try await toolUndo(arguments)
        default: throw MCPError.unknownTool(name)
        }
    }

    private func toolScan(_ arguments: [String: Any]) async throws -> String {
        let paths = (arguments["paths"] as? [String] ?? []).map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        }
        // Local-only and AI-off by construction: MCP never uploads content.
        let (outcome, plan) = try await orchestrator.scan(
            mode: paths.isEmpty ? .homeFolder : .selectedFolders,
            selectedFolders: paths,
            providerSettings: ProviderSettings(),
            includeAI: false,
            posture: .conservative,
            duplicateStrategy: Self.strategy(from: arguments["duplicate_strategy"] as? String)
        )
        var filesByID: [String: FileRecord] = [:]
        for record in outcome.files {
            filesByID[record.id] = record
        }
        lastScan = ScanState(outcome: outcome, plan: plan, filesByID: filesByID)

        let duplicateFindings = outcome.findings.filter { $0.category == .duplicate }
        let duplicateBytes = plan.actions
            .filter { $0.actionType == .cloneDeduplicate || $0.actionType == .moveToTrash }
            .reduce(Int64(0)) { total, action in
                total + action.targets.reduce(Int64(0)) { sum, id in sum + (filesByID[id]?.sizeBytes ?? 0) }
            }
        var lines = [
            "Scan finished: \(outcome.files.count) files looked at, "
                + "\(outcome.findings.count) findings (\(duplicateFindings.count) duplicate groups).",
            "Plan proposes \(plan.actions.count) actions reclaiming about \(bytes(duplicateBytes)).",
            "Next: list_findings, then show_plan for a group, then check_finding before execute."
        ]
        for finding in duplicateFindings.prefix(10) {
            lines.append("- [\(Self.shortID(finding.id))] \(finding.summary) (\(bytes(finding.bytesReclaimable)))")
        }
        return lines.joined(separator: "\n")
    }

    private func toolListFindings(_ arguments: [String: Any]) throws -> String {
        guard let lastScan else { throw MCPError.noScan }
        let query = (arguments["query"] as? String ?? "").lowercased()
        let limit = max(1, (arguments["limit"] as? Int) ?? 20)
        let matches = lastScan.outcome.findings.filter { finding in
            query.isEmpty
                || finding.summary.lowercased().contains(query)
                || finding.targetFileIDs.contains {
                    lastScan.filesByID[$0]?.displayPath.lowercased().contains(query) == true
                }
        }
        guard !matches.isEmpty else { return "No findings match." }
        var lines = ["\(matches.count) findings (showing up to \(limit)):"]
        for finding in matches.prefix(limit) {
            lines.append("- [\(Self.shortID(finding.id))] \(finding.summary) · \(bytes(finding.bytesReclaimable))")
        }
        return lines.joined(separator: "\n")
    }

    private func toolShowPlan(_ arguments: [String: Any]) throws -> String {
        guard let lastScan else { throw MCPError.noScan }
        let findingID = arguments["finding_id"] as? String
        let actions = lastScan.plan.actions.filter { action in
            guard let findingID else { return true }
            return action.findingID?.hasPrefix(findingID) == true
        }
        guard !actions.isEmpty else { return "No plan actions for this query." }
        var lines = ["\(actions.count) proposed actions:"]
        for action in actions {
            let targetBytes = action.targets
                .compactMap { lastScan.filesByID[$0]?.sizeBytes }
                .reduce(Int64(0), +)
            let label = action.actionType == .cloneDeduplicate
                ? "fold onto keeper (nothing deleted)"
                : action.actionType.rawValue
            lines.append(
                "- [\(Self.shortID(action.id))] \(label): \(action.targets.count) files, "
                + "\(bytes(targetBytes)), risk \(action.risk.rawValue) · \(action.reason)"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Live re-verification: every file in the group must still exist, still
    /// carry the scanned identity, and still hash to the scanned SHA-256 —
    /// a stale plan never gets executed on changed files.
    private func toolCheckFinding(_ arguments: [String: Any]) async throws -> String {
        guard let lastScan else { throw MCPError.noScan }
        let id = arguments["finding_id"] as? String ?? ""
        guard let finding = lastScan.outcome.findings.first(where: { $0.id.hasPrefix(id) }) else {
            throw MCPError.unknownFinding(id)
        }
        var present = 0
        var identical = 0
        var missing: [String] = []
        var changed: [String] = []
        let scannedHash = finding.evidence["hash"]
        for fileID in finding.targetFileIDs {
            guard let record = lastScan.filesByID[fileID] else { continue }
            switch checkMember(record, scannedHash: scannedHash) {
            case .identical:
                present += 1
                identical += 1
            case .resized:
                present += 1
                changed.append(record.displayPath)
            case .missing:
                missing.append(record.displayPath)
            }
        }
        var lines = [
            "Checked \(finding.targetFileIDs.count) files: \(present) present and correct size, "
                + "\(identical) byte-identical to the scan."
        ]
        if !missing.isEmpty {
            lines.append("Missing or resized since the scan: \(missing.joined(separator: ", "))")
        }
        if !changed.isEmpty {
            lines.append("Contents changed since the scan: \(changed.joined(separator: ", "))")
        }
        if missing.isEmpty && changed.isEmpty {
            lines.append("The plan is still safe to execute.")
        } else {
            lines.append("Re-scan before executing: the stale plan no longer matches the disk.")
        }
        return lines.joined(separator: "\n")
    }

    /// Outcome of re-reading one finding member from disk.
    private enum MemberCheck {
        case identical
        case resized
        case missing
    }

    /// Re-reads one file: present, correct size, and (for exact-duplicate
    /// findings, where every member shares one hash) byte-identical.
    private func checkMember(_ record: FileRecord, scannedHash: String?) -> MemberCheck {
        let attributes = try? FileManager.default.attributesOfItem(atPath: record.url.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.int64Value
        guard FileManager.default.fileExists(atPath: record.url.path),
              let scannedSize = record.identity.sizeBytes,
              currentSize == scannedSize else {
            return .missing
        }
        guard let hash = try? FingerprintService.fullHash(for: record.url) else {
            return .resized
        }
        if let scannedHash {
            return hash == scannedHash ? .identical : .resized
        }
        return .identical
    }

    private func toolExecute(_ arguments: [String: Any]) async throws -> String {
        guard let lastScan else { throw MCPError.noScan }
        let confirm = arguments["confirm"] as? Bool == true
        let requestedIDs = arguments["action_ids"] as? [String]
        let pending = lastScan.plan.actions.filter { action in
            action.userDecision == .undecided && action.executedAt == nil
                && (requestedIDs == nil || requestedIDs?.contains(where: { action.id.hasPrefix($0) }) == true)
        }
        guard !pending.isEmpty else { throw MCPError.unknownAction(requestedIDs?.joined(separator: ", ") ?? "any") }
        // High-risk destructive work stays behind the app's explicit
        // confirmation flow; MCP never bypasses it.
        if pending.contains(where: { $0.risk >= .high }) {
            throw MCPError.highRiskRequiresApp
        }

        let targetBytes = pending.reduce(Int64(0)) { total, action in
            total + action.targets.reduce(Int64(0)) { sum, id in
                sum + (lastScan.filesByID[id]?.sizeBytes ?? 0)
            }
        }
        let summaryText = pending.map { action -> String in
            let label = action.actionType == .cloneDeduplicate
                ? "fold \(action.targets.count) files onto their keepers (nothing deleted)"
                : "\(action.actionType.rawValue): \(action.targets.count) files"
            return "- \(label) · \(action.reason)"
        }.joined(separator: "\n")

        guard confirm else {
            return """
            Dry run. Nothing changed. Would \(pending.count) actions affecting \(bytes(targetBytes)):
            \(summaryText)
            Ask the user, then call execute again with confirm: true.
            """
        }

        var approved: [PlannedAction] = []
        for action in pending {
            var approvedAction = action
            approvedAction.userDecision = .approved
            approvedAction.status = .approved
            approved.append(approvedAction)
        }
        let summary = await executor.execute(actions: approved, filesByID: lastScan.filesByID)
        // Stamp the in-memory plan so a second confirmed execute can never
        // re-run the same actions (the executor's idempotency guard reads
        // executedAt off the plan).
        var plan = lastScan.plan
        let stamped = Set(approved.map(\.id))
        for index in plan.actions.indices where stamped.contains(plan.actions[index].id) {
            plan.actions[index].executedAt = Date()
            plan.actions[index].status = summary.failedActionIDs.contains(plan.actions[index].id)
                ? .failed : .completed
        }
        self.lastScan = ScanState(outcome: lastScan.outcome, plan: plan, filesByID: lastScan.filesByID)
        var lines = [
            "Executed \(approved.count) actions: \(summary.undoRecords.count) undo records created, "
                + "\(summary.failures.count) failures."
        ]
        for failure in summary.failures.prefix(10) {
            lines.append("! \(failure)")
        }
        return lines.joined(separator: "\n")
    }

    private func toolHistory() async throws -> String {
        // The store returns records newest-first already.
        let records = Array(try await store.loadUndoRecords().prefix(20))
        guard !records.isEmpty else { return "No recorded operations yet." }
        var lines = ["Last \(records.count) operations (newest first):"]
        for record in records {
            let path = record.restoreURL?.path ?? record.trashURL?.path ?? "?"
            lines.append(
                "- op [\(record.operationLogID.prefix(8))] \(record.inverseAction.rawValue)"
                    + " \(path) · \(record.status.rawValue)"
            )
        }
        return lines.joined(separator: "\n")
    }

    private func toolUndo(_ arguments: [String: Any]) async throws -> String {
        let id = arguments["operation_log_id"] as? String ?? ""
        var records = try await store.loadUndoRecords(operationLogID: id)
        if records.isEmpty {
            // History lists 8-character prefixes; resolve those against full ids.
            records = try await store.loadUndoRecords().filter { $0.operationLogID.hasPrefix(id) }
        }
        let restorable = records.filter { $0.status == .available }
        guard !restorable.isEmpty else { throw MCPError.nothingToUndo(id) }
        let paths = restorable.compactMap { $0.restoreURL?.path ?? $0.trashURL?.path }

        guard arguments["confirm"] as? Bool == true else {
            return """
            Dry run. Nothing changed. Undoing operation \(id) would restore \(restorable.count) items:
            \(paths.joined(separator: "\n"))
            Ask the user, then call undo again with confirm: true.
            """
        }
        var restored = 0
        var failures: [String] = []
        for record in restorable {
            do {
                _ = try await undoService.restore(record)
                restored += 1
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        var lines = ["Restored \(restored) of \(restorable.count) items."]
        failures.prefix(10).forEach { lines.append("! \($0)") }
        return lines.joined(separator: "\n")
    }

    /// Local byte formatter — ByteFormatting is internal to Core, and MCP is
    /// a separate module.
    private func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

}

// Tool catalog, JSON-schema builders and JSON-RPC payload helpers live outside
// the main class body.
extension MCPKit {
    // MARK: - Payload helpers

    static func responsePayload(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    public static func errorPayload(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    /// Serializes and prints one response line. Sorted keys keep the output
    /// stable for tests. Writes through FileHandle (not `print`) because
    /// stdio pipes are block-buffered — a buffered response would strand the
    /// client waiting for a line that never arrives.
    public static func emit(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func strategy(from raw: String?) -> DuplicateStrategy {
        raw == "move_to_trash" ? .moveToTrash : .apfsClone
    }

    static func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }


    /// Tool descriptors for tools/list. Argument names match the schema keys.
    static var toolDescriptions: [[String: Any]] {
        [
            tool(
                "scan",
                "Scan the Mac for cleanup opportunities (duplicate files, caches, old downloads). "
                    + "Changes nothing. Default duplicate strategy folds exact duplicates into APFS "
                    + "clones, which deletes nothing.",
                [
                    "paths": stringArray("Folders to scan. Omit to scan the whole home folder."),
                    "duplicate_strategy": string("apfs_clone (default, deletes nothing) or move_to_trash.")
                ]
            ),
            tool(
                "list_findings",
                "List findings from the last scan with their ids, summaries and reclaimable bytes.",
                [
                    "query": string("Filter by summary or file path substring."),
                    "limit": integer("How many to return (default 20).")
                ]
            ),
            tool(
                "show_plan",
                "Show the proposed actions, optionally for one finding.",
                ["finding_id": string("Finding id (or its first characters) from list_findings.")]
            ),
            tool(
                "check_finding",
                "Re-read a finding's files from disk now: still present, still the scanned "
                    + "identity, still byte-identical. Always check before executing a stale plan.",
                ["finding_id": string("Finding id from list_findings.")]
            ),
            tool(
                "execute",
                "Run proposed actions after the user agrees. Without confirm: true this is a dry "
                    + "run that only describes what would happen. Ask the user first, then call "
                    + "again with confirm: true. High-risk destructive actions are refused here and "
                    + "must be approved in the app.",
                [
                    "action_ids": stringArray("Action ids to run; omit for every pending action."),
                    "confirm": boolean("true to actually execute; false or missing for a dry run.")
                ]
            ),
            tool(
                "history",
                "List recent operations that can be undone.",
                [:]
            ),
            tool(
                "undo",
                "Restore what an executed operation changed. Without confirm: true it only "
                    + "describes the restore. Ask the user first.",
                [
                    "operation_log_id": string("Operation id from history."),
                    "confirm": boolean("true to actually undo; false or missing for a dry run.")
                ]
            )
        ]
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties
            ]
        ]
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func integer(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private static func boolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private static func stringArray(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "description": description]
    }
}
