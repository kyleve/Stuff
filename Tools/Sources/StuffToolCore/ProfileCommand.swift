import ArgumentParser
import Darwin
import Foundation

public struct ProfileCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "./profile",
        abstract: "Report clean-build and test timing hot spots.",
        discussion: """
        Runs a clean build-for-testing and the unit and snapshot test legs, then
        reports build phases, slow type-check sites, tests, bundles, and walls.
        Slow timings never fail the command; failed build or test legs do.
        """,
    )

    @Flag(name: .customLong("build-only"), help: "Only profile the build.")
    var buildOnly = false

    @Flag(name: .customLong("tests-only"), help: "Only profile the tests.")
    var testsOnly = false

    @Flag(name: .customLong("no-snapshots"), help: "Skip the snapshot test leg.")
    var noSnapshots = false

    @Flag(name: .customLong("ci-shape"), help: "Use separate cold DerivedData per test job.")
    var ciShape = false

    @Option(help: "Simulator device name.")
    var device = "iPhone 17"

    @Option(help: "Simulator iOS version.")
    var os = "27.0"

    @Option(help: "Number of slowest tests to list.")
    var top = 15

    @Option(name: .customLong("test-threshold"), help: "Test hot-spot threshold in seconds.")
    var testThreshold = 0.1

    @Option(
        name: .customLong("typecheck-threshold"),
        help: "Type-check warning threshold in milliseconds.",
    )
    var typeCheckThreshold = 100

    public init() {}

    public mutating func validate() throws {
        guard buildOnly == false || testsOnly == false else {
            throw ValidationError("--build-only and --tests-only cannot be combined")
        }
        guard device.isEmpty == false else { throw ValidationError("--device requires a value") }
        guard os.isEmpty == false else { throw ValidationError("--os requires a value") }
        guard top > 0 else { throw ValidationError("--top must be greater than zero") }
        guard testThreshold.isFinite, testThreshold >= 0 else {
            throw ValidationError("--test-threshold must be zero or greater")
        }
        guard typeCheckThreshold >= 0 else {
            throw ValidationError("--typecheck-threshold must be zero or greater")
        }
    }

    public func makeRequest() -> ProfileRequest {
        ProfileRequest(
            build: testsOnly == false,
            tests: buildOnly == false,
            snapshots: noSnapshots == false,
            ciShape: ciShape,
            device: device,
            os: os,
            top: top,
            testThreshold: testThreshold,
            typeCheckThreshold: typeCheckThreshold,
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
        let service = ProfileService(
            runner: runner,
            simulator: simulator,
            fileSystem: fileSystem,
            clock: clock,
            terminal: terminal,
            repository: repository,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            environment: environment,
        )
        do {
            let status = try await service.run(makeRequest())
            if status != 0 { throw ExitCode(status) }
        } catch let failure as ProfileServiceFailure {
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
