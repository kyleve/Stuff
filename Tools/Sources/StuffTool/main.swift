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
            writeOrExit("error: unknown Stuff tool selector '\(selector)'", to: .standardError)
            Darwin.exit(EXIT_FAILURE)
        }

        let commandArguments = Array(arguments.dropFirst())
        if commandArguments.isEmpty,
           let termination = command.noArgumentTermination
        {
            writeOrExit(termination.message, to: termination.stream)
            Darwin.exit(termination.exitCode)
        }

        do {
            var parsed = try command.commandType.parseAsRoot(commandArguments)
            if var asynchronous = parsed as? any AsyncParsableCommand {
                try await asynchronous.run()
            } else {
                try parsed.run()
            }
            Darwin.exit(EXIT_SUCCESS)
        } catch {
            if isBrokenPipe(error) {
                Darwin.exit(128 + SIGPIPE)
            }
            let termination = command.termination(for: error)
            if termination.message.isEmpty == false {
                writeOrExit(termination.message, to: termination.stream)
            }
            Darwin.exit(termination.exitCode)
        }
    }

    private static func writeOrExit(_ message: String, to stream: TerminalStream) {
        let handle = switch stream {
            case .standardOutput: FileHandle.standardOutput
            case .standardError: FileHandle.standardError
        }
        do {
            try handle.write(contentsOf: Data((message + "\n").utf8))
        } catch {
            Darwin.exit(isBrokenPipe(error) ? 128 + SIGPIPE : EXIT_FAILURE)
        }
    }

    private static func isBrokenPipe(_ error: any Error) -> Bool {
        var current: NSError? = error as NSError
        while let candidate = current {
            if candidate.domain == NSPOSIXErrorDomain, candidate.code == EPIPE {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
