import ArgumentParser
import Foundation

/// `porthole mcp` — serve the paired app as an MCP server over stdio.
///
/// The real implementation lands with PortholeMCP; until then this exits with a
/// clear message rather than pretending to serve.
struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve a paired app as an MCP server over stdio.",
    )

    @OptionGroup var appOption: AppOption

    func run() async throws {
        throw CleanExit.message("`porthole mcp` is added in the next step (PortholeMCP).")
    }
}
