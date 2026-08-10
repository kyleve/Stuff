import ArgumentParser
import Darwin
import Foundation
import StuffToolCore

@main
enum StuffTool {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let selector = arguments.first,
              let command = PublicCommand(rawValue: selector)
        else {
            let selector = arguments.first ?? ""
            write("error: unknown Stuff tool selector '\(selector)'", to: .standardError)
            Darwin.exit(EXIT_FAILURE)
        }

        do {
            var parsed = try command.commandType.parseAsRoot(Array(arguments.dropFirst()))
            if var asynchronous = parsed as? any AsyncParsableCommand {
                try await asynchronous.run()
            } else {
                try parsed.run()
            }
            Darwin.exit(EXIT_SUCCESS)
        } catch {
            let termination = command.termination(for: error)
            if termination.message.isEmpty == false {
                write(termination.message, to: termination.stream)
            }
            Darwin.exit(termination.exitCode)
        }
    }

    private static func write(_ message: String, to stream: TerminalStream) {
        let handle = switch stream {
            case .standardOutput: FileHandle.standardOutput
            case .standardError: FileHandle.standardError
        }
        do {
            try handle.write(contentsOf: Data((message + "\n").utf8))
        } catch {
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
