import Foundation
import MacOSCleanerCore

// Tidybyte MCP server: newline-delimited JSON-RPC over stdio. Point an
// MCP client at the built binary; tools and the mandatory dry-run/confirm
// flow live in MCPKit.
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

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8),
          let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        MCPKit.emit(MCPKit.errorPayload(id: NSNull(), code: -32700, message: "Parse error"))
        continue
    }
    if let response = await kit.handle(request: request) {
        MCPKit.emit(response)
    }
}
