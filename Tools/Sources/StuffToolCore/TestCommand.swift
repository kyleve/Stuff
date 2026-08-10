import ArgumentParser
import Darwin
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run Stuff's iOS tests through the repository-owned simulator.",
        discussion: """
        With no scope, runs the bundles affected by changes against origin/main,
        including committed, uncommitted, and untracked files. Every invocation
        first runs the host-side backup upgrader regression.
        """,
    )

    @Argument(help: "Test bundle names to run.")
    var bundles: [String] = []

    @Flag(help: "Run the full unit suite (Stuff-iOS-Tests).")
    var all = false

    @Flag(help: "Run the image-snapshot suite (StuffSnapshotTests).")
    var snapshots = false

    @Flag(help: "Run both the unit and image-snapshot suites.")
    var everything = false

    @Option(help: "An xcodebuild test identifier; repeatable.")
    var only: [String] = []

    @Option(help: "Git reference used for affected-bundle selection.")
    var base = "origin/main"

    @Flag(name: .customLong("no-build"), help: "Reuse the last test build.")
    var noBuild = false

    @Flag(name: .customLong("no-generate"), help: "Skip Tuist project generation.")
    var noGenerate = false

    @Option(help: "Re-record snapshots: all, failed, missing, or never.")
    var record: String?

    @Option(help: "Simulator device name.")
    var device = "iPhone 17"

    @Option(help: "Simulator iOS version.")
    var os = "27.0"

    @Flag(help: "Use an existing shared simulator instead of this checkout's device.")
    var shared = false

    @Option(name: .customLong("snapshot-shard"), help: "Snapshot shard: 1/2 or 2/2.")
    var snapshotShard: String?

    @Flag(help: "Print per-phase snapshot capture timings.")
    var timings = false

    @Flag(help: "Describe every differing snapshot.")
    var review = false

    @Option(help: "Seconds between non-interactive progress lines.")
    var heartbeat: Double = 15

    @Option(name: .customLong("status-file"), help: "Write the latest progress line here.")
    var statusFile: String?

    @Option(
        name: .customLong("timing-report"),
        help: "Write versioned per-suite snapshot durations here.",
    )
    var timingReport: String?

    public init() {}

    public mutating func validate() throws {
        guard base.isEmpty == false else { throw ValidationError("--base requires a git ref") }
        guard device.isEmpty == false else { throw ValidationError("--device requires a value") }
        guard os.isEmpty == false else { throw ValidationError("--os requires a value") }
        guard only.allSatisfy({ $0.isEmpty == false }) else {
            throw ValidationError("--only requires a test identifier")
        }
        guard statusFile?.isEmpty != true else {
            throw ValidationError("--status-file requires a path")
        }
        guard timingReport?.isEmpty != true else {
            throw ValidationError("--timing-report requires a path")
        }
        let scopes = [all, snapshots, everything].count(where: { $0 })
        guard scopes <= 1 else {
            throw ValidationError("choose only one of --all, --snapshots, or --everything")
        }
        if let record, ["all", "failed", "missing", "never"].contains(record) == false {
            throw ValidationError(
                "--record must be all, failed, missing or never (got '\(record)')",
            )
        }
        if let snapshotShard {
            guard ["1/2", "2/2"].contains(snapshotShard) else {
                throw ValidationError(
                    "--snapshot-shard must be 1/2 or 2/2 (got '\(snapshotShard)')",
                )
            }
            guard snapshots else {
                throw ValidationError("--snapshot-shard requires --snapshots")
            }
            guard only.isEmpty else {
                throw ValidationError("--snapshot-shard cannot be combined with --only")
            }
        }
        guard heartbeat.isFinite, heartbeat > 0 else {
            throw ValidationError("--heartbeat must be greater than zero")
        }
    }

    public func makeRequest() -> TestRequest {
        TestRequest(
            scope: selectedScope,
            bundles: bundles,
            only: only,
            baseReference: base,
            build: noBuild == false,
            generate: noGenerate == false,
            record: record,
            device: device,
            os: os,
            sharedSimulator: shared,
            snapshotShard: snapshotShard,
            timings: timings,
            review: review,
            heartbeat: heartbeat,
            statusFile: statusFile,
            timingReport: timingReport,
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
        let service = TestService(
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
        } catch let failure as TestServiceFailure {
            switch failure {
                case let .message(message):
                    try await terminal.write("error: \(message)\n", to: .standardError)
                    throw ExitCode.failure
                case let .exitCode(code):
                    throw ExitCode(code)
                case .reported:
                    throw ExitCode.failure
            }
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

    private var selectedScope: TestScope {
        if bundles.isEmpty == false { return .bundles }
        if all { return .all }
        if snapshots { return .snapshots }
        if everything { return .everything }
        if only.isEmpty == false { return .only }
        return .changed
    }
}
