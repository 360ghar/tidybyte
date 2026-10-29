import Foundation
@testable import MacOSCleanerCore
@testable import MacOSCleanerMCPLibrary
import XCTest

/// MCP server dispatcher tests: the JSON-RPC contract (initialize, ping,
/// tools/list, unknown methods, notifications) and the mandatory
/// dry-run-then-confirm gating — without touching the filesystem.
final class MCPServerTests: XCTestCase {
    private func makeKit() throws -> MCPKit {
        MCPKit(store: try SQLiteStore.inMemory())
    }

    private func handle(_ kit: MCPKit, _ request: [String: Any]) async throws -> [String: Any] {
        let response = await kit.handle(request: request)
        return try XCTUnwrap(response)
    }

    private func toolCall(id: String, name: String, arguments: [String: Any] = [:]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
    }

    private func textResult(of response: [String: Any]) throws -> String {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return try XCTUnwrap(content.first?["text"] as? String)
    }

    func testInitializeEchoesClientProtocolVersion() async throws {
        let kit = try makeKit()
        let response = try await handle(kit, [
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2024-11-05"]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "tidybyte-mcp")
        XCTAssertEqual(response["id"] as? Int, 1)
    }

    func testPingAndToolsList() async throws {
        let kit = try makeKit()
        let ping = try await handle(kit, ["jsonrpc": "2.0", "id": "p", "method": "ping"])
        XCTAssertTrue((ping["result"] as? [String: Any])?.isEmpty == true)

        let listed = try await handle(kit, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let result = try XCTUnwrap(listed["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertEqual(
            names,
            ["scan", "list_findings", "show_plan", "check_finding", "execute", "history", "undo"],
            "The tool surface is part of the agent-facing contract"
        )
        // Every tool declares an object input schema.
        for tool in tools {
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")
        }
    }

    func testUnknownMethodReturnsProtocolError() async throws {
        let kit = try makeKit()
        let response = try await handle(kit, ["jsonrpc": "2.0", "id": 3, "method": "resources/list"])
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testNotificationProducesNoResponse() async throws {
        let kit = try makeKit()
        let response = await kit.handle(request: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(response, "Requests without an id are notifications and get no reply")
    }

    func testExecuteBeforeScanFailsAsToolError() async throws {
        let kit = try makeKit()
        let response = try await handle(kit, toolCall(id: "4", name: "execute", arguments: ["confirm": true]))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = try textResult(of: response)
        XCTAssertTrue(text.contains("No scan"), "Agent-visible guidance expected, got: \(text)")
    }

    func testExecuteDocumentsItsConfirmGate() async throws {
        // Without a scan the call refuses to run at all — nothing can execute
        // before the user has seen a plan. The tool's own description must
        // carry the dry-run/confirm contract for the agent.
        let kit = try makeKit()
        let response = try await handle(kit, toolCall(id: "5", name: "execute"))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)

        let listed = try await handle(kit, ["jsonrpc": "2.0", "id": 6, "method": "tools/list"])
        let tools = try XCTUnwrap((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let executeTool = try XCTUnwrap(tools.first { ($0["name"] as? String) == "execute" })
        let description = try XCTUnwrap(executeTool["description"] as? String)
        XCTAssertTrue(description.contains("confirm"), "execute must document its confirm gate")
    }

    func testUnknownToolIsAnError() async throws {
        let kit = try makeKit()
        let response = try await handle(kit, toolCall(id: "7", name: "format_disk"))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = try textResult(of: response)
        XCTAssertTrue(text.contains("Unknown tool"))
    }
}
