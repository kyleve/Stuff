import ArgumentParser

public struct TestCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "./test",
        abstract: "Run Stuff's iOS tests through the repository-owned simulator.",
        discussion: """
        With no scope, runs the bundles affected by changes against origin/main,
        including committed, uncommitted, and untracked files. Every normal
        invocation first runs the Bumper Bowling architecture checks. Affected
        and unit-capable scopes also run the host-side backup upgrader regression.
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

    @Option(
        name: .customLong("only-file"),
        help: "Read newline-delimited Bundle/Suite identifiers.",
    )
    var onlyFile: String?

    @Option(help: "Git reference used for affected-bundle selection (default: origin/main).")
    var base: String?

    @Flag(
        name: .customLong("architecture-only"),
        help: "Run only Bumper configuration, rule tests, and lint.",
    )
    var architectureOnly = false

    @Flag(
        name: .customLong("skip-architecture"),
        help: "Skip Bumper checks because another CI job owns them.",
    )
    var skipArchitecture = false

    @Flag(name: .customLong("no-build"), help: "Reuse the last test build.")
    var noBuild = false

    @Flag(name: .customLong("no-generate"), help: "Skip Tuist project generation.")
    var noGenerate = false

    @Option(
        name: .customLong("build-artifacts"),
        help: "Build selected schemes into a portable artifact directory without testing.",
    )
    var buildArtifacts: String?

    @Option(
        name: .customLong("test-artifacts"),
        help: "Run tests from a portable artifact directory.",
    )
    var testArtifacts: String?

    @Option(
        name: .customLong("enumerate-suites"),
        help: "Write selected artifact Bundle/Suite identifiers to a path.",
    )
    var enumerateSuites: String?

    @Option(help: "Re-record snapshots: all, failed, missing, or never.")
    var record: String?

    @Option(help: "Simulator device name (default: iPhone 17).")
    var device: String?

    @Option(help: "Simulator iOS version (default: 27.0).")
    var os: String?

    @Flag(help: "Use an existing shared simulator instead of this checkout's device.")
    var shared = false

    @Flag(help: "Print per-phase snapshot capture timings.")
    var timings = false

    @Flag(help: "Describe every differing snapshot.")
    var review = false

    @Option(help: "Seconds between non-interactive progress lines (default: 15).")
    var heartbeat: Double?

    @Option(name: .customLong("status-file"), help: "Write the latest progress line here.")
    var statusFile: String?

    public init() {}

    public mutating func validate() throws {
        guard base?.isEmpty != true else { throw ValidationError("--base requires a git ref") }
        guard device?.isEmpty != true else { throw ValidationError("--device requires a value") }
        guard os?.isEmpty != true else { throw ValidationError("--os requires a value") }
        guard only.allSatisfy({ $0.isEmpty == false }) else {
            throw ValidationError("--only requires a test identifier")
        }
        guard onlyFile?.isEmpty != true else {
            throw ValidationError("--only-file requires a path")
        }
        guard buildArtifacts?.isEmpty != true else {
            throw ValidationError("--build-artifacts requires a directory")
        }
        guard testArtifacts?.isEmpty != true else {
            throw ValidationError("--test-artifacts requires a directory")
        }
        guard enumerateSuites?.isEmpty != true else {
            throw ValidationError("--enumerate-suites requires a path")
        }
        guard statusFile?.isEmpty != true else {
            throw ValidationError("--status-file requires a path")
        }
        let scopes = [all, snapshots, everything].count(where: { $0 })
        guard scopes <= 1 else {
            throw ValidationError("choose only one of --all, --snapshots, or --everything")
        }
        guard bundles.isEmpty || scopes == 0 else {
            throw ValidationError(
                "bundle names cannot be combined with --all, --snapshots, or --everything",
            )
        }
        if let record, ["all", "failed", "missing", "never"].contains(record) == false {
            throw ValidationError(
                "--record must be all, failed, missing or never (got '\(record)')",
            )
        }
        if let heartbeat {
            guard heartbeat.isFinite, heartbeat > 0 else {
                throw ValidationError("--heartbeat must be greater than zero")
            }
        }
        guard architectureOnly == false || skipArchitecture == false else {
            throw ValidationError(
                "--architecture-only cannot be combined with --skip-architecture",
            )
        }
        guard architectureOnly == false || hasTestArguments == false else {
            throw ValidationError(
                "--architecture-only cannot be combined with test options or bundles",
            )
        }
        guard buildArtifacts == nil || testArtifacts == nil else {
            throw ValidationError(
                "--build-artifacts cannot be combined with --test-artifacts",
            )
        }
        guard buildArtifacts == nil ||
            (noBuild == false && onlyFile == nil && only.isEmpty && enumerateSuites == nil)
        else {
            throw ValidationError(
                "--build-artifacts cannot be combined with test filters or test-only modes",
            )
        }
        guard enumerateSuites == nil || testArtifacts != nil else {
            throw ValidationError("--enumerate-suites requires --test-artifacts")
        }
        guard enumerateSuites == nil || selectedScope == .snapshots else {
            throw ValidationError("--enumerate-suites requires --snapshots")
        }
    }

    public func makeRequest() -> TestRequest {
        TestRequest(
            scope: selectedScope,
            bundles: bundles,
            only: only,
            onlyFile: onlyFile,
            baseReference: base ?? "origin/main",
            architectureMode: architectureOnly ? .only : (skipArchitecture ? .skip : .run),
            artifactMode: artifactMode,
            build: testArtifacts == nil && noBuild == false,
            generate: testArtifacts == nil && noGenerate == false,
            record: record,
            device: device ?? "iPhone 17",
            os: os ?? "27.0",
            sharedSimulator: shared,
            timings: timings,
            review: review,
            heartbeat: heartbeat ?? 15,
            statusFile: statusFile,
        )
    }

    public mutating func run() async throws {
        let runtime = ToolRuntime()
        let status = try await performPublicCommand(terminal: runtime.terminal) {
            try await runtime.testService().run(makeRequest())
        }
        if status != 0 { throw ExitCode(status) }
    }

    private var selectedScope: TestScope {
        if bundles.isEmpty == false { return .bundles }
        if all { return .all }
        if snapshots { return .snapshots }
        if everything { return .everything }
        if only.isEmpty == false || onlyFile != nil { return .only }
        return .changed
    }

    private var artifactMode: TestArtifactMode {
        if let buildArtifacts { return .build(directory: buildArtifacts) }
        if let testArtifacts {
            return .test(directory: testArtifacts, enumerateSuites: enumerateSuites)
        }
        return .local
    }

    private var hasTestArguments: Bool {
        bundles.isEmpty == false || all || snapshots || everything || only.isEmpty == false ||
            onlyFile != nil || base != nil || noBuild || noGenerate || buildArtifacts != nil ||
            testArtifacts != nil || enumerateSuites != nil || record != nil || device != nil ||
            os != nil || shared || timings || review || heartbeat != nil || statusFile != nil
    }
}
