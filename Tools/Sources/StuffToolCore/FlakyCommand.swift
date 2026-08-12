import ArgumentParser

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
        let runtime = ToolRuntime()
        let status = try await performPublicCommand(terminal: runtime.terminal) {
            try await runtime.flakyService().run(makeRequest())
        }
        if status != 0 { throw ExitCode(status) }
    }
}
