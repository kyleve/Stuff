import ArgumentParser
import Darwin
import Foundation

public struct SimulatorCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "simulator",
        abstract: "Resolve this checkout's iOS Simulator by UDID.",
        discussion: """
        Each checkout owns a separate device. Progress and warnings go to
        stderr; resolve mode writes only the selected UDID to stdout.
        """,
    )

    @Option(help: "Simulator device name.")
    var device = "iPhone 17"

    @Option(help: "Simulator iOS version.")
    var os = "27.0"

    @Flag(name: .customLong("no-boot"), help: "Resolve without booting the device.")
    var noBoot = false

    @Flag(help: "Use an existing shared device instead of a checkout-owned one.")
    var shared = false

    @Flag(help: "List every checkout-owned and unowned Stuff simulator.")
    var list = false

    @Flag(help: "Delete stale registry entries and devices for deleted checkouts.")
    var prune = false

    @Flag(help: "Preview prune, delete, or recreate without changing anything.")
    var dryRun = false

    @Flag(help: "Delete this checkout's device.")
    var delete = false

    @Flag(help: "Delete and recreate this checkout's device.")
    var recreate = false

    public init() {}

    public mutating func run() async throws {
        let terminal = StandardTerminal()
        do {
            let mode = try selectedMode()
            let environment = ProcessInfo.processInfo.environment
            let repository = environment["STUFF_REPOSITORY_ROOT"]
                .map { URL(filePath: $0, directoryHint: .isDirectory) }
                ?? URL(
                    filePath: FileManager.default.currentDirectoryPath,
                    directoryHint: .isDirectory,
                )
            let service = SimulatorService(
                runner: CommandRunner(),
                fileSystem: FoundationFileSystem(),
                clock: ContinuousToolClock(),
                processInspector: SystemProcessInspector(),
                terminal: terminal,
                repository: repository,
                home: FileManager.default.homeDirectoryForCurrentUser,
                temporaryDirectory: FileManager.default.temporaryDirectory,
                processID: getpid(),
            )
            _ = try await service.run(
                SimulatorRequest(
                    device: device,
                    os: os,
                    boot: noBoot == false,
                    shared: shared,
                    dryRun: dryRun,
                    mode: mode,
                ),
            )
        } catch let failure as SimulatorFailure {
            if case let .message(message) = failure {
                try await terminal.write("error: \(message)\n", to: .standardError)
            }
            throw ExitCode.failure
        } catch let failure as DirectoryLockFailure {
            try await terminal.write("error: \(failure)\n", to: .standardError)
            throw ExitCode.failure
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            try await terminal.write("error: \(error)\n", to: .standardError)
            throw ExitCode.failure
        }
    }

    private func selectedMode() throws -> SimulatorMode {
        let selected: [SimulatorMode] = [
            list ? .list : nil,
            prune ? .prune : nil,
            delete ? .delete : nil,
            recreate ? .recreate : nil,
        ].compactMap(\.self)
        guard selected.count <= 1 else {
            throw SimulatorFailure.message(
                "choose only one of --list, --prune, --delete, or --recreate",
            )
        }
        return selected.first ?? .resolve
    }
}
