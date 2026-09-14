import Foundation
import PortholeCore
@testable import PortholeRemote
import Testing

struct PortholeMCPServerTests {
    @Test func catalogReadsRequireBoundedPages() async throws {
        let server = makeServer(effect: .read)
        _ = try await response(server, method: "initialize", requestID: 1, parameters: .object([:]))
        _ = try await server
            .respond(to: Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                    .utf8))
        let scope = try JSONDecoder().decode(
            PortholeValue.self,
            from: JSONEncoder().encode(PortholeRemoteTestSupport.scope),
        )
        let result = try await response(
            server,
            method: "tools/call",
            requestID: 2,
            parameters: .object([
                "name": .string("porthole_capabilities"),
                "arguments": .object(["scope": scope, "offset": .integer(0), "limit": .integer(1)]),
            ]),
        )
        guard case let .object(toolResult) = result["result"],
              case let .array(content) = toolResult["content"],
              case let .object(first) = content.first,
              case let .string(text) = first["text"]
        else { Issue.record("Expected catalog page"); return }
        let page = try JSONDecoder().decode(PortholeCapabilityPage.self, from: Data(text.utf8))
        #expect(page.offset == 0)
        #expect(page.total == 1)
        #expect(page.items.count == 1)
        let unbounded = try await response(
            server,
            method: "tools/call",
            requestID: 3,
            parameters: .object([
                "name": .string("porthole_capabilities"),
                "arguments": .object(
                    ["scope": scope, "offset": .integer(0), "limit": .integer(201)],
                ),
            ]),
        )
        guard case let .object(failed) = unbounded["result"]
        else { Issue.record("Expected rejected page"); return }
        #expect(failed["isError"] == .bool(true))
    }

    @Test func requiresInitializationAndOffersOnlyThreeExecutorTools() async throws {
        let server = makeServer(effect: .read)
        let before = try await response(
            server,
            method: "tools/list",
            requestID: 1,
            parameters: .object([:]),
        )
        #expect(before["error"] != nil)
        let initialized = try await response(
            server,
            method: "initialize",
            requestID: 2,
            parameters: .object(["protocolVersion": .string("2025-11-25")]),
        )
        guard case let .object(result) = initialized["result"]
        else { Issue.record("Expected initialize result"); return }
        #expect(result["protocolVersion"] == .string("2025-11-25"))
        #expect(try await server.respond(to: JSONEncoder().encode(PortholeValue.object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/initialized"),
        ]))) == nil)
        let listed = try await response(
            server,
            method: "tools/list",
            requestID: 3,
            parameters: .object([:]),
        )
        guard case let .object(list) = listed["result"],
              case let .array(tools) = list["tools"] else { Issue.record("Expected tools"); return }
        #expect(tools.count == 3)
        #expect(try !String(decoding: JSONEncoder().encode(tools), as: UTF8.self)
            .contains("porthole_approve"))
    }

    @Test func approvalIsStructuredEvidenceAndNeverAnMCPApprovalCommand() async throws {
        let server = makeServer(effect: .unknown)
        _ = try await response(server, method: "initialize", requestID: 1, parameters: .object([:]))
        _ = try await server
            .respond(to: Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                    .utf8))
        let invocation = try JSONDecoder().decode(
            PortholeValue.self,
            from: JSONEncoder().encode(PortholeRemoteTestSupport.invocation()),
        )
        let result = try await response(
            server,
            method: "tools/call",
            requestID: 2,
            parameters: .object([
                "name": .string("porthole_invoke"),
                "arguments": .object(["invocation": invocation]),
            ]),
        )
        let encoded = try String(decoding: JSONEncoder().encode(result), as: UTF8.self)
        #expect(encoded.contains("approval_required"))
        let denied = try await response(
            server,
            method: "tools/call",
            requestID: 3,
            parameters: .object(["name": .string("porthole_approve")]),
        )
        #expect(denied["error"] != nil)
    }

    private func makeServer(effect: PortholeEffect) -> PortholeMCPServer {
        PortholeMCPServer(
            client: PortholeRemoteClient(
                transport: PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
                    .dispatcher(executor: PortholeRemoteTestExecutor(effect: effect))),
            ),
        )
    }

    private func response(
        _ server: PortholeMCPServer,
        method: String,
        requestID: Int64,
        parameters: PortholeValue,
    ) async throws -> [String: PortholeValue] {
        let request = PortholeValue.object([
            "jsonrpc": .string("2.0"),
            "id": .integer(requestID),
            "method": .string(method),
            "params": parameters,
        ])
        let data = try #require(await server.respond(to: JSONEncoder().encode(request)))
        guard case let .object(value) = try JSONDecoder().decode(PortholeValue.self, from: data)
        else { throw PortholeRemoteError.invalidMessage }
        return value
    }
}
