import ArgumentParser
import Darwin
import Foundation
import StuffToolCore

@main
enum StuffTool {
    private enum SupervisionEvent {
        case cancellationGraceExpired
        case commandFinished(Int32)
        case signal(SignalForwardingReport)
    }

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let selector = arguments.first,
              let command = PublicCommand(rawValue: selector)
        else {
            let selector = arguments.first ?? ""
            _ = write("error: unknown Stuff tool selector '\(selector)'", to: .standardError)
            Darwin.exit(EXIT_FAILURE)
        }

        let relay = CommandSignalRelay()
        let (events, continuation) = AsyncStream.makeStream(
            of: SupervisionEvent.self,
            bufferingPolicy: .unbounded,
        )
        let signalSource = SystemSignalSource(relay: relay) { report in
            continuation.yield(.signal(report))
        }
        let commandArguments = Array(arguments.dropFirst())
        let commandTask = Task {
            let exitCode = await CommandSignalRelay.$current.withValue(relay) {
                await run(command, arguments: commandArguments, relay: relay)
            }
            continuation.yield(.commandFinished(exitCode))
            return exitCode
        }
        var cancellationGraceTask: Task<Void, Never>?

        for await event in events {
            switch event {
                case .cancellationGraceExpired:
                    commandTask.cancel()
                case let .commandFinished(exitCode):
                    cancellationGraceTask?.cancel()
                    _ = await cancellationGraceTask?.value
                    _ = await commandTask.value
                    continuation.finish()
                    reportFailures(relay.forwardingFailures)
                    if let commandSignal = relay.firstSignal {
                        signalSource.terminate(with: commandSignal)
                    }
                    signalSource.stop()
                    Darwin.exit(exitCode)
                case let .signal(report):
                    switch report.stage {
                        case .first:
                            reportFailures(report.failures)
                            cancellationGraceTask = Task {
                                try? await Task.sleep(for: .seconds(1))
                                guard Task.isCancelled == false else { return }
                                continuation.yield(.cancellationGraceExpired)
                            }
                        case .repeated:
                            cancellationGraceTask?.cancel()
                            commandTask.cancel()
                            await relay.waitUntilSafeToExitAfterForcedSignal()
                            continuation.finish()
                            reportFailures(relay.forwardingFailures)
                            signalSource.terminate(with: report.firstSignal)
                    }
            }
        }

        commandTask.cancel()
        _ = await commandTask.value
        signalSource.stop()
        Darwin.exit(EXIT_FAILURE)
    }

    private static func run(
        _ command: PublicCommand,
        arguments: [String],
        relay: CommandSignalRelay,
    ) async -> Int32 {
        do {
            try Task.checkCancellation()
            var parsed = try command.commandType.parseAsRoot(arguments)
            if var asynchronous = parsed as? any AsyncParsableCommand {
                try await asynchronous.run()
            } else {
                try parsed.run()
            }
            return EXIT_SUCCESS
        } catch {
            if let commandSignal = relay.firstSignal {
                return 128 + commandSignal.rawValue
            }
            if isBrokenPipe(error) {
                return relay.receiveBrokenPipeError()?.exitCode
                    ?? relay.firstSignal.map { 128 + $0.rawValue }
                    ?? (128 + CommandSignal.brokenPipe.rawValue)
            }
            let termination = command.termination(for: error)
            if termination.message.isEmpty == false {
                guard write(termination.message, to: termination.stream) else {
                    return relay.firstSignal.map { 128 + $0.rawValue } ?? EXIT_FAILURE
                }
            }
            return termination.exitCode
        }
    }

    private static func reportFailures(_ failures: [SignalForwardingFailure]) {
        for failure in failures {
            let reason = String(cString: strerror(failure.errorNumber))
            _ = write(
                "warning: could not forward signal \(failure.signal.rawValue) "
                    + "to process group \(failure.processGroupID): \(reason)",
                to: .standardError,
            )
        }
    }

    @discardableResult
    private static func write(_ message: String, to stream: TerminalStream) -> Bool {
        let handle = switch stream {
            case .standardOutput: FileHandle.standardOutput
            case .standardError: FileHandle.standardError
        }
        do {
            try handle.write(contentsOf: Data((message + "\n").utf8))
            return true
        } catch {
            if isBrokenPipe(error),
               let relay = CommandSignalRelay.current,
               relay.firstSignal == nil
            {
                relay.receiveBrokenPipeError()
            }
            return false
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
