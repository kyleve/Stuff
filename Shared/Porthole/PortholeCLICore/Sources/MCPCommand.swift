import ArgumentParser
import Foundation
import PortholeMCP

/// `porthole mcp` — serve the paired app as an MCP server over stdio, for an
/// agent (e.g. Cursor) to launch.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve a paired app as an MCP server over stdio.",
    )

    @OptionGroup var appOption: AppOption

    func run() async throws {
        let paired = try CLIRuntime.resolveApp(appOption.app)
        let session = try await CLIRuntime.makeClient().connect(to: paired)
        let server = PortholeMCPServer(session: session, serverName: "porthole-\(paired.appName)")
        try await server.run()
    }
}
