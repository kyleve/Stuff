import ArgumentParser
import Foundation

public struct LedgerInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "./Ledger/install",
        abstract: "Build Ledger in Release and install it to /Applications.",
        discussion: """
        Produces an ad-hoc-signed standalone app, safely stops only the installed
        executable, replaces it through a rollback transaction, and launches it.
        """,
    )

    @Flag(name: .customLong("no-open"), help: "Install without launching Ledger.")
    var noOpen = false

    @Flag(help: "Describe the build and replacement without changing anything.")
    var dryRun = false

    public init() {}

    public func makeRequest() -> LedgerInstallRequest {
        LedgerInstallRequest(openAfterInstall: noOpen == false, dryRun: dryRun)
    }

    public mutating func run() async throws {
        let terminal = StandardTerminal()
        let environment = ProcessInfo.processInfo.environment
        let repository = environment["STUFF_REPOSITORY_ROOT"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory,
            )
        let service = LedgerInstallService(
            runner: CommandRunner(),
            fileSystem: FoundationFileSystem(),
            clock: ContinuousToolClock(),
            terminal: terminal,
            repository: repository,
            applicationsDirectory: URL(filePath: "/Applications", directoryHint: .isDirectory),
            temporaryDirectory: FileManager.default.temporaryDirectory,
            identifier: { UUID().uuidString },
            terminationPolicy: ProcessTerminationPolicy(
                graceChecks: 50,
                forceChecks: 10,
                interval: .milliseconds(100),
            ),
        )
        do {
            let status = try await service.run(makeRequest())
            if status != 0 { throw ExitCode(status) }
        } catch let failure as LedgerInstallFailure {
            switch failure {
                case let .message(message):
                    try await terminal.write("error: \(message)\n", to: .standardError)
                    throw ExitCode.failure
                case let .exitCode(code):
                    throw ExitCode(code)
            }
        } catch let failure as InstalledProcessFailure {
            try await terminal.write("error: \(failure)\n", to: .standardError)
            switch failure {
                case .message:
                    throw ExitCode.failure
                case let .exitCode(code):
                    throw ExitCode(code)
            }
        } catch let failure as FileReplacementTransactionFailure {
            try await terminal.write("error: \(failure)\n", to: .standardError)
            throw ExitCode.failure
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            try await terminal.write("error: \(error)\n", to: .standardError)
            throw ExitCode.failure
        }
    }
}
