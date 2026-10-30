import Foundation
import MacOSCleanerCore
import MacOSCleanerMCPLibrary

// Tidybyte MCP server: newline-delimited JSON-RPC over stdio. Point an
// MCP client at the built binary; tools and the dry-run/confirm flow live
// in MCPKit (destructive actions are refused there by policy and must be
// approved in the app).
//
// TIDYBYTE_DB redirects the SQLite database (tests / e2e runs) so
// scripted servers never touch the user's real history.

func makeStore() throws -> SQLiteStore {
    if let override = ProcessInfo.processInfo.environment["TIDYBYTE_DB"] {
        return try SQLiteStore(databaseURL: URL(fileURLWithPath: override))
    }
    return try SQLiteStore()
}

let kit: MCPKit
do {
    kit = try MCPKit(store: makeStore())
} catch {
    // Same fallback rule as the app bootstrap: a temporary database beats
    // refusing to start — scans still work, history is session-only.
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("tidybyte-mcp-\(UUID().uuidString).sqlite")
    kit = try MCPKit(store: SQLiteStore(databaseURL: temporary))
}

// readLine blocks, so it runs on its own thread and feeds the request loop
// through a stream. The loop still processes ONE request at a time (MCPKit's
// state stays serial), but input keeps flowing while a long scan runs, so a
// `notifications/cancelled` can abort the in-flight request instead of
// head-of-line-blocking until it finishes.
let lines = AsyncStream<String> { continuation in
    Task.detached(priority: .userInitiated) {
        while let line = readLine(strippingNewline: true) {
            continuation.yield(line)
        }
        continuation.finish()
    }
}

var inFlight: Task<Data?, Never>?
for await line in lines {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
        // Unparseable bytes — JSON-RPC "Parse error".
        MCPKit.emit(MCPKit.errorPayload(id: NSNull(), code: -32700, message: "Parse error"))
        continue
    }
    // Well-formed JSON that is not a request object (an array/scalar) is an
    // "Invalid Request" (-32600), not a parse error. MCP removed batch
    // support, so arrays are rejected outright.
    guard let object = request as? [String: Any] else {
        MCPKit.emit(MCPKit.errorPayload(id: NSNull(), code: -32600, message: "Invalid Request"))
        continue
    }
    if object["id"] == nil {
        // Notifications get no reply. The one that matters: cancel the
        // in-flight request so a stuck scan does not block the session.
        if (object["method"] as? String) == "notifications/cancelled" {
            inFlight?.cancel()
        }
        continue
    }
    // Serialize the response inside the task so only Sendable Data crosses
    // back; the request object is loop-local and unreachable by the reader,
    // so passing it in unchecked is sound.
    nonisolated(unsafe) let requestObject = object
    let task = Task { () -> Data? in
        guard let response = await kit.handle(request: requestObject) else { return nil }
        return try? JSONSerialization.data(withJSONObject: response.payload, options: [.sortedKeys])
    }
    inFlight = task
    if let responseData = await task.value, !task.isCancelled {
        MCPKit.emitRaw(responseData)
    } else if task.isCancelled {
        // The client cancelled this id: reply with the JSON-RPC cancellation
        // error instead of a result it is no longer waiting to act on.
        MCPKit.emit(MCPKit.errorPayload(id: object["id"] as Any, code: -32800, message: "Request cancelled"))
    }
    inFlight = nil
}
