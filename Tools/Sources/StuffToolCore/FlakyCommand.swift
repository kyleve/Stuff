import ArgumentParser
import Darwin
import Foundation

public enum FlakyRelaunch: String, CaseIterable, ExpressibleByArgument, Sendable {
    case yes = "YES"
    case no = "NO"
}

public struct FlakyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "./flaky",
        abstract: "Detect flaky tests with suite runs and isolated repetitions.",
        discussion: """
        Builds once, repeatedly runs the complete scheme, then tight-loops every
        test that failed. Test failures are report-only; prerequisite and build
        failures still exit nonzero.
        """,
    )

    @Option(name: .customLong("suite-runs"), help: "Full-suite runs in phase one.")
    var suiteRuns = 10

    @Option(help: "Isolated repetitions per suspect in phase two.")
    var iterations = 50

    @Option(help: "Simulator device name.")
    var device = "iPhone 17"

    @Option(help: "Simulator iOS version.")
    var os = "27.0"

    @Option(help: "Xcode scheme to test.")
    var scheme = "Stuff-iOS-Tests"

    @Option(help: "Start a new process for each isolated repetition.")
    var relaunch = FlakyRelaunch.yes

    @Flag(name: .customLong("no-update"), help: "Do not replace FLAKY_TESTS.md.")
    var noUpdate = false

    @Flag(help: "Run the detector without replacing FLAKY_TESTS.md.")
    var dryRun = false

    @Option(help: "Maximum number of flaky tests to report.")
    var top: Int?

    public init() {}

    public mutating func validate() throws {
        guard suiteRuns > 0 else {
            throw ValidationError("--suite-runs must be greater than zero")
        }
        guard iterations > 0 else {
            throw ValidationError("--iterations must be greater than zero")
        }
        guard device.isEmpty == false else { throw ValidationError("--device requires a value") }
        guard os.isEmpty == false else { throw ValidationError("--os requires a value") }
        guard scheme.isEmpty == false else { throw ValidationError("--scheme requires a value") }
        if let top, top <= 0 {
            throw ValidationError("--top must be greater than zero")
        }
    }

    public func makeRequest() -> FlakyRequest {
        FlakyRequest(
            suiteRuns: suiteRuns,
            iterations: iterations,
            device: device,
            os: os,
            scheme: scheme,
            relaunch: relaunch,
            updateReport: noUpdate == false && dryRun == false,
            top: top,
        )
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
        let runner = CommandRunner()
        let fileSystem = FoundationFileSystem()
        let clock = ContinuousToolClock()
        let simulator = SimulatorService(
            runner: runner,
            fileSystem: fileSystem,
            clock: clock,
            processInspector: SystemProcessInspector(),
            terminal: StandardErrorOnlyTerminal(base: terminal),
            repository: repository,
            home: FileManager.default.homeDirectoryForCurrentUser,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            processID: getpid(),
        )
        let service = FlakyService(
            runner: runner,
            simulator: simulator,
            fileSystem: fileSystem,
            clock: clock,
            terminal: terminal,
            repository: repository,
            home: FileManager.default.homeDirectoryForCurrentUser,
            environment: environment,
        )
        do {
            let status = try await service.run(makeRequest())
            if status != 0 { throw ExitCode(status) }
        } catch let failure as FlakyServiceFailure {
            switch failure {
                case let .message(message):
                    try await terminal.write("error: \(message)\n", to: .standardError)
                    throw ExitCode.failure
                case let .exitCode(code):
                    throw ExitCode(code)
            }
        } catch let failure as SimulatorFailure {
            if case let .message(message) = failure {
                try await terminal.write("error: \(message)\n", to: .standardError)
            }
            throw ExitCode(failure.exitStatus)
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
}
