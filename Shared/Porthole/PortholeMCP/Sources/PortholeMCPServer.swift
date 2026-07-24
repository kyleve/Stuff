import Foundation
import MCP
import PortholeClientKit
import PortholeCore

/// Serves a connected Porthole session as an MCP server over stdio: it turns the
/// device manifest into MCP tools (`porthole_overview`, `act_*`, `query_*`,
/// `tail_*`) and routes tool calls through a ``PortholeMCPDispatcher``.
public struct PortholeMCPServer: Sendable {
    private let session: any PortholeSessionProviding
    private let serverName: String

    public init(session: any PortholeSessionProviding, serverName: String) {
        self.session = session
        self.serverName = serverName
    }

    /// Fetches the manifest, registers handlers, and serves stdio until the
    /// input stream closes.
    public func run() async throws {
        let manifests = try await session.manifest()
        let dispatcher = PortholeMCPDispatcher(session: session, manifests: manifests)
        let plan = dispatcher.plannedTools()

        let server = Server(
            name: serverName,
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false)),
        )

        let tools = plan.map { planned in
            Tool(
                name: planned.name,
                description: planned.description,
                inputSchema: MCPValueBridge.toMCP(planned.inputSchema),
            )
        }

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = PortholeValue
                .object((params.arguments ?? [:]).mapValues(MCPValueBridge.toPorthole))
            let result = await dispatcher.call(name: params.name, arguments: arguments)
            switch result {
                case let .json(value):
                    return CallTool.Result(
                        content: [.text(text: MCPValueBridge.jsonString(value))],
                        isError: false,
                    )
                case let .image(data):
                    return CallTool.Result(
                        content: [.image(data: data.base64EncodedString(), mimeType: "image/png")],
                        isError: false,
                    )
                case let .failure(message):
                    return CallTool.Result(content: [.text(text: message)], isError: true)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
