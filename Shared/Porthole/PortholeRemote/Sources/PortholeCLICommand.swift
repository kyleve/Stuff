import Foundation

/// Positional command parsing is separate from credentials, file reads, and network effects.
public enum PortholeCLICommand: Sendable, Equatable {
    case help
    case discover
    case paired
    case pair
    case application(server: String)
    case capabilities(server: String, scopeFile: String)
    case invoke(server: String, invocationFile: String)
    case watch(server: String, invocationFile: String)
    case mcp(server: String)

    public static func parse(_ arguments: [String]) throws -> Self {
        guard let command = arguments.first else { return .help }
        let values = Array(arguments.dropFirst())
        switch command {
            case "help", "--help",
                 "-h": guard values.isEmpty
                else { throw PortholeRemoteError.invalidMessage }; return .help
            case "discover": guard values.isEmpty
                else { throw PortholeRemoteError.invalidMessage }; return .discover
            case "paired": guard values.isEmpty
                else { throw PortholeRemoteError.invalidMessage }; return .paired
            case "pair": guard values.isEmpty
                else { throw PortholeRemoteError.invalidMessage }; return .pair
            case "application": guard values.count == 1
                else { throw PortholeRemoteError.invalidMessage
                }; return .application(server: values[0])
            case "capabilities": guard values.count == 2
                else { throw PortholeRemoteError.invalidMessage }; return .capabilities(
                    server: values[0],
                    scopeFile: values[1],
                )
            case "invoke": guard values.count == 2
                else { throw PortholeRemoteError.invalidMessage }; return .invoke(
                    server: values[0],
                    invocationFile: values[1],
                )
            case "watch": guard values.count == 2
                else { throw PortholeRemoteError.invalidMessage }; return .watch(
                    server: values[0],
                    invocationFile: values[1],
                )
            case "mcp": guard values.count == 1
                else { throw PortholeRemoteError.invalidMessage }; return .mcp(server: values[0])
            default: throw PortholeRemoteError.invalidMessage
        }
    }

    public static let usage = """
    Usage: porthole <command>
      discover                         Watch nearby Porthole applications
      paired                           List enrolled applications
      pair                             Read a one-time invitation from stdin
      application <server>             Read current application scopes
      capabilities <server> <file>     Read APIs for a scope JSON file
      invoke <server> <file>           Invoke a complete invocation JSON file
      watch <server> <file>            Watch the runtime's latest read sample
      mcp <server>                     Serve MCP JSON-RPC over stdin/stdout

    Use a service name from 'paired' as <server>. Use '-' to read JSON from stdin.
    Live changes require approval in the app. After approval, reuse the exact
    invocation file. A failed connection never causes an automatic retry.
    """
}
