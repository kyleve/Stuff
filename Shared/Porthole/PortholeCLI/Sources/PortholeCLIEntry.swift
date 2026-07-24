import ArgumentParser
import PortholeCLICore

/// Entry point for the `porthole` tool. Parses the root command and dispatches
/// asynchronously — the explicit form (rather than `await PortholeCommand.main()`)
/// so the async subcommand `run()` methods are actually awaited.
@main
enum PortholeCLIEntry {
    static func main() async {
        do {
            let command = try PortholeCommand.parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                var syncCommand = command
                try syncCommand.run()
            }
        } catch {
            PortholeCommand.exit(withError: error)
        }
    }
}
