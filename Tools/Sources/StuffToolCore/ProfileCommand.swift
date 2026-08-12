import ArgumentParser

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
            scope: testsOnly ? .tests : (buildOnly ? .build : .all),
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
        let runtime = ToolRuntime()
        let status = try await performPublicCommand(terminal: runtime.terminal) {
            try await runtime.profileService().run(makeRequest())
        }
        if status != 0 { throw ExitCode(status) }
    }
}
