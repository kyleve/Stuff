import Foundation

public enum ProfileScope: Equatable, Sendable {
    case build
    case tests
    case all

    var includesBuild: Bool {
        self != .tests
    }

    var includesTests: Bool {
        self != .build
    }
}

public struct ProfileRequest: Equatable, Sendable {
    public let scope: ProfileScope
    public let snapshots: Bool
    public let ciShape: Bool
    public let device: String
    public let os: String
    public let top: Int
    public let testThreshold: Double
    public let typeCheckThreshold: Int

    public init(
        scope: ProfileScope,
        snapshots: Bool,
        ciShape: Bool,
        device: String,
        os: String,
        top: Int,
        testThreshold: Double,
        typeCheckThreshold: Int,
    ) {
        self.scope = scope
        self.snapshots = snapshots
        self.ciShape = ciShape
        self.device = device
        self.os = os
        self.top = top
        self.testThreshold = testThreshold
        self.typeCheckThreshold = typeCheckThreshold
    }
}

/// Runs the build and test legs whose timings make up `./profile`.
public struct ProfileService: Sendable {
    private static let workspace = "Stuff.xcworkspace"
    private static let unitScheme = "Stuff-iOS-Tests"
    private static let snapshotScheme = "StuffSnapshotTests"
    private static let separator = String(repeating: "=", count: 60)

    private struct Paths {
        let work: URL
        let derived: URL
        let snapshotDerived: URL
        let generationLog: URL
        let buildLog: URL
        let testLog: URL
        let resultBundle: URL
        let testsJSON: URL
        let snapshotBuildLog: URL
        let snapshotTestLog: URL
        let snapshotResultBundle: URL
        let snapshotTestsJSON: URL
        let snapshotTimings: URL
    }

    private struct Walls {
        var simulator = 0
        var generation = 0
        var unitBuildSettings = 0
        var snapshotBuildSettings = 0
        var build: Int?
        var unitTest: Int?
        var snapshotBuild: Int?
        var snapshotTest: Int?
    }

    private let runner: any CommandRunning
    private let simulator: any SimulatorResolving
    private let fileSystem: any FileSystem
    private let clock: any ToolClock
    private let terminal: any Terminal
    private let repository: URL
    private let temporaryDirectory: URL
    private let environment: [String: String]
    private let xcodeWorkspace: XcodeWorkspace

    public init(
        runner: any CommandRunning,
        simulator: any SimulatorResolving,
        fileSystem: any FileSystem,
        clock: any ToolClock,
        terminal: any Terminal,
        repository: URL,
        temporaryDirectory: URL,
        environment: [String: String],
    ) {
        self.runner = runner
        self.simulator = simulator
        self.fileSystem = fileSystem
        self.clock = clock
        self.terminal = terminal
        self.repository = repository
        self.temporaryDirectory = temporaryDirectory
        self.environment = environment
        xcodeWorkspace = XcodeWorkspace(
            runner: runner,
            fileSystem: fileSystem,
            repository: repository,
            workspace: Self.workspace,
        )
    }

    public func run(_ request: ProfileRequest) async throws -> Int32 {
        var walls = Walls()
        let simulatorStart = await clock.now()
        let udid = try await simulator.resolve(
            device: request.device,
            os: request.os,
            shared: false,
        )
        walls.simulator = await elapsedSeconds(since: simulatorStart)
        let destination = "platform=iOS Simulator,id=\(udid)"
        let paths = try makePaths(ciShape: request.ciShape)
        let typeCheckFlags = "$(inherited) " +
            "-Xfrontend -warn-long-function-bodies=\(request.typeCheckThreshold) " +
            "-Xfrontend -warn-long-expression-type-checking=\(request.typeCheckThreshold)"

        try await terminal.write(
            "==> Regenerating project (tuist generate --no-open)\n",
            to: .standardOutput,
        )
        let generationStart = await clock.now()
        let generation = try await xcodeWorkspace.generateProject(
            logURL: paths.generationLog,
            outputHandler: { stream, bytes in
                if stream == .standardError {
                    try await terminal.write(bytes, to: .standardError)
                }
            },
        )
        walls.generation = await elapsedSeconds(since: generationStart)
        guard generation.succeeded else {
            throw ToolFailure.exitCode(generation.exitCode)
        }

        var unitEnvironment: [String: String] = [:]
        let unitSettingsStart = await clock.now()
        if let products = try await xcodeWorkspace.builtProductsDirectory(
            scheme: Self.unitScheme,
            destination: destination,
            derivedData: paths.derived,
        ) {
            unitEnvironment["TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH"] = products
        } else {
            try await terminal.write(
                "warning: could not resolve BUILT_PRODUCTS_DIR; package resource " +
                    "bundle lookups will fall back to the linker's placement\n",
                to: .standardError,
            )
        }
        walls.unitBuildSettings = await elapsedSeconds(since: unitSettingsStart)

        var snapshotEnvironment = ["TEST_RUNNER_SNAPSHOT_TIMING": "1"]
        if request.scope.includesTests, request.snapshots {
            let settingsStart = await clock.now()
            if let products = try await xcodeWorkspace.builtProductsDirectory(
                scheme: Self.snapshotScheme,
                destination: destination,
                derivedData: paths.snapshotDerived,
            ) {
                snapshotEnvironment["TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH"] = products
            } else {
                try await terminal.write(
                    "warning: could not resolve snapshot BUILT_PRODUCTS_DIR; package resource " +
                        "bundle lookups will fall back to the linker's placement\n",
                    to: .standardError,
                )
            }
            walls.snapshotBuildSettings = await elapsedSeconds(since: settingsStart)
        }

        if request.scope.includesBuild {
            try await terminal.write(
                "==> Clean build-for-testing on \(request.device) / iOS \(request.os) (cold build)\n",
                to: .standardOutput,
            )
            let start = await clock.now()
            let result = try await xcodeWorkspace.xcodebuild(
                [
                    "clean",
                    "build-for-testing",
                    "-workspace",
                    Self.workspace,
                    "-scheme",
                    Self.unitScheme,
                    "-destination",
                    destination,
                    "-derivedDataPath",
                    paths.derived.path,
                    "-showBuildTimingSummary",
                    "OTHER_SWIFT_FLAGS=\(typeCheckFlags)",
                ],
                environment: [:],
                logURL: paths.buildLog,
            )
            walls.build = await elapsedSeconds(since: start)
            guard result.succeeded else {
                try await printFailure(
                    "build failed (exit \(result.exitCode))",
                    logURL: paths.buildLog,
                    tailLines: 30,
                )
                throw ToolFailure.exitCode(result.exitCode)
            }
            try await printSection(
                "BUILD HOT SPOTS  —  cold build wall: \(walls.build ?? 0)s",
            )
            do {
                let report = try BuildTimingReport(log: fileSystem.read(paths.buildLog))
                try await terminal.write(
                    report.text(typeCheckThreshold: request.typeCheckThreshold),
                    to: .standardOutput,
                )
            } catch {
                try await terminal.write(
                    "warning: couldn't parse build timing from \(paths.buildLog.path) " +
                        "(\(error))\n",
                    to: .standardError,
                )
            }
            try await terminal.write("\n", to: .standardOutput)
        }

        var catalogs: [XCResultTestCatalog] = []
        var unitWallLabel = ""
        var snapshotBuildLabel: String?
        if request.scope.includesTests {
            let unitAction: String
            if request.scope.includesBuild {
                unitAction = "test-without-building"
                unitWallLabel = "test-execution wall"
                try await terminal.write(
                    "==> Running unit tests (test-without-building, reuses the build above)\n",
                    to: .standardOutput,
                )
            } else {
                unitAction = "test"
                unitWallLabel = "build+test wall"
                try await terminal.write(
                    "==> Running unit tests (build + test) on \(request.device) / iOS \(request.os)\n",
                    to: .standardOutput,
                )
            }
            try xcodeWorkspace.removeIfPresent(paths.resultBundle)
            let start = await clock.now()
            let result = try await xcodeWorkspace.xcodebuild(
                [
                    unitAction,
                    "-workspace",
                    Self.workspace,
                    "-scheme",
                    Self.unitScheme,
                    "-destination",
                    destination,
                    "-derivedDataPath",
                    paths.derived.path,
                    "-resultBundlePath",
                    paths.resultBundle.path,
                    "-collect-test-diagnostics",
                    "never",
                ],
                environment: unitEnvironment,
                logURL: paths.testLog,
            )
            walls.unitTest = await elapsedSeconds(since: start)
            guard result.succeeded else {
                try await printFailure(
                    "unit-test leg (\(Self.unitScheme)) failed (exit \(result.exitCode))",
                    logURL: paths.testLog,
                    tailLines: 40,
                )
                throw ToolFailure.exitCode(result.exitCode)
            }
            if let catalog = try await readCatalog(
                resultBundle: paths.resultBundle,
                output: paths.testsJSON,
            ) {
                catalogs.append(catalog)
            }

            if request.snapshots {
                if request.scope.includesBuild {
                    let buildArguments: [String]
                    if request.ciShape {
                        buildArguments = ["clean", "build-for-testing"]
                        snapshotBuildLabel = "cold, separate DerivedData matching CI"
                    } else {
                        buildArguments = ["build-for-testing"]
                        snapshotBuildLabel = "incremental, reuses the unit build"
                    }
                    try await terminal.write(
                        "==> \(buildArguments.joined(separator: " ")) \(Self.snapshotScheme) " +
                            "(\(snapshotBuildLabel ?? ""))\n",
                        to: .standardOutput,
                    )
                    let snapshotBuildStart = await clock.now()
                    let snapshotBuild = try await xcodeWorkspace.xcodebuild(
                        buildArguments + [
                            "-workspace",
                            Self.workspace,
                            "-scheme",
                            Self.snapshotScheme,
                            "-destination",
                            destination,
                            "-derivedDataPath",
                            paths.snapshotDerived.path,
                            "OTHER_SWIFT_FLAGS=\(typeCheckFlags)",
                        ],
                        environment: [:],
                        logURL: paths.snapshotBuildLog,
                    )
                    walls.snapshotBuild = await elapsedSeconds(since: snapshotBuildStart)
                    guard snapshotBuild.succeeded else {
                        try await printFailure(
                            "snapshot build (\(Self.snapshotScheme)) failed " +
                                "(exit \(snapshotBuild.exitCode))",
                            logURL: paths.snapshotBuildLog,
                            tailLines: 30,
                        )
                        throw ToolFailure.exitCode(snapshotBuild.exitCode)
                    }
                    try await terminal.write(
                        "    snapshot build (\(snapshotBuildLabel ?? "")): " +
                            "\(walls.snapshotBuild ?? 0)s\n",
                        to: .standardOutput,
                    )
                    try await terminal.write(
                        "==> Running snapshot tests (test-without-building, " +
                            "\(Self.snapshotScheme) scheme — serial by design, ~10-15 min)\n",
                        to: .standardOutput,
                    )
                } else {
                    try await terminal.write(
                        "==> Running snapshot tests (build + test, \(Self.snapshotScheme) " +
                            "scheme — serial by design, ~10-15 min)\n",
                        to: .standardOutput,
                    )
                }
                try xcodeWorkspace.removeIfPresent(paths.snapshotResultBundle)
                let snapshotStart = await clock.now()
                let snapshotResult = try await xcodeWorkspace.xcodebuild(
                    [
                        request.scope.includesBuild ? "test-without-building" : "test",
                        "-workspace",
                        Self.workspace,
                        "-scheme",
                        Self.snapshotScheme,
                        "-destination",
                        destination,
                        "-derivedDataPath",
                        paths.snapshotDerived.path,
                        "-resultBundlePath",
                        paths.snapshotResultBundle.path,
                        "-collect-test-diagnostics",
                        "never",
                    ],
                    environment: snapshotEnvironment,
                    logURL: paths.snapshotTestLog,
                )
                walls.snapshotTest = await elapsedSeconds(since: snapshotStart)
                guard snapshotResult.succeeded else {
                    try await printFailure(
                        "snapshot-test leg (\(Self.snapshotScheme)) failed " +
                            "(exit \(snapshotResult.exitCode))",
                        logURL: paths.snapshotTestLog,
                        tailLines: 40,
                    )
                    try await terminal.write(
                        "note: a red snapshot leg usually means failed image comparisons " +
                            "(e.g. stale references on this branch), not a profile bug — " +
                            "rerun with --no-snapshots to profile without it.\n",
                        to: .standardError,
                    )
                    throw ToolFailure.exitCode(snapshotResult.exitCode)
                }
                if let catalog = try await readCatalog(
                    resultBundle: paths.snapshotResultBundle,
                    output: paths.snapshotTestsJSON,
                ) {
                    catalogs.append(catalog)
                }
                try await printSnapshotTimingReport(paths: paths)
            }

            let wallSummary = request.snapshots
                ? "\(unitWallLabel): \(walls.unitTest ?? 0)s (unit) + " +
                "\(walls.snapshotTest ?? 0)s (snapshot)"
                : "\(unitWallLabel): \(walls.unitTest ?? 0)s"
            try await printSection("TEST HOT SPOTS  —  \(wallSummary)")
            if catalogs.isEmpty == false {
                try await terminal.write(
                    TestHotSpotReport(catalogs: catalogs).text(
                        top: request.top,
                        threshold: request.testThreshold,
                    ),
                    to: .standardOutput,
                )
            }
            try await terminal.write("\n", to: .standardOutput)
        }

        try await printWalls(
            walls,
            request: request,
            unitWallLabel: unitWallLabel,
            snapshotBuildLabel: snapshotBuildLabel,
        )
        try await terminal.write(
            "Logs and result bundles: \(paths.work.path)\n",
            to: .standardOutput,
        )
        return 0
    }

    private func makePaths(ciShape: Bool) throws -> Paths {
        let configured = environment["PROFILE_WORKDIR"].flatMap { path in
            path.isEmpty ? nil : resolveUserPath(path)
        }
        let work = configured ?? temporaryDirectory.appending(
            path: "where-profile-\(xcodeWorkspace.checkoutIdentifier)",
            directoryHint: .isDirectory,
        )
        try fileSystem.createDirectory(at: work, withIntermediateDirectories: true)
        try fileSystem.setPosixPermissions(0o700, at: work)
        let derived = work.appending(path: "DerivedData", directoryHint: .isDirectory)
        return Paths(
            work: work,
            derived: derived,
            snapshotDerived: ciShape
                ? work.appending(path: "SnapshotDerivedData", directoryHint: .isDirectory)
                : derived,
            generationLog: work.appending(path: "generate.log"),
            buildLog: work.appending(path: "build.log"),
            testLog: work.appending(path: "test.log"),
            resultBundle: work.appending(path: "tests.xcresult", directoryHint: .isDirectory),
            testsJSON: work.appending(path: "tests.json"),
            snapshotBuildLog: work.appending(path: "snapshot-build.log"),
            snapshotTestLog: work.appending(path: "snapshot-test.log"),
            snapshotResultBundle: work.appending(
                path: "snapshot-tests.xcresult",
                directoryHint: .isDirectory,
            ),
            snapshotTestsJSON: work.appending(path: "snapshot-tests.json"),
            snapshotTimings: work.appending(path: "snapshot-timings.jsonl"),
        )
    }

    private func readCatalog(resultBundle: URL, output: URL) async throws -> XCResultTestCatalog? {
        do {
            return try await xcodeWorkspace.testCatalog(at: resultBundle, exportingTo: output)
        } catch is DecodingError {
            try await terminal.write(
                "warning: couldn't parse test results from \(output.path)\n",
                to: .standardError,
            )
            return nil
        } catch {
            throw ToolFailure.message(String(describing: error))
        }
    }

    private func printSnapshotTimingReport(paths: Paths) async throws {
        let log: Data
        do {
            log = try fileSystem.read(paths.snapshotTestLog)
        } catch {
            try await terminal.write(
                "warning: couldn't read snapshot timing log \(paths.snapshotTestLog.path) " +
                    "(\(error))\n",
                to: .standardError,
            )
            return
        }
        let payloads = String(decoding: log, as: UTF8.self).split(separator: "\n")
            .compactMap { line -> String? in
                guard let range = line.range(of: "SNAPSHOT_TIMING ") else { return nil }
                return String(line[range.upperBound...])
            }
        let jsonLines = payloads.isEmpty ? "" : payloads.joined(separator: "\n") + "\n"
        try fileSystem.write(Data(jsonLines.utf8), to: paths.snapshotTimings, atomically: false)
        try await printSection("SNAPSHOT CAPTURE PHASES")
        do {
            let report = try SnapshotLogReport(logs: [log])
            try await terminal.write(report.profileTimingText(), to: .standardOutput)
        } catch {
            try await terminal.write(
                "warning: couldn't parse snapshot timing from \(paths.snapshotTestLog.path) " +
                    "(\(error))\n",
                to: .standardError,
            )
        }
    }

    private func printWalls(
        _ walls: Walls,
        request: ProfileRequest,
        unitWallLabel: String,
        snapshotBuildLabel: String?,
    ) async throws {
        try await printSection("PROFILE WALLS")
        try await terminal.write(
            "  simulator resolve/boot: \(walls.simulator)s\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "  project generation: \(walls.generation)s\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "  unit build settings: \(walls.unitBuildSettings)s\n",
            to: .standardOutput,
        )
        if request.scope.includesTests, request.snapshots {
            try await terminal.write(
                "  snapshot build settings: \(walls.snapshotBuildSettings)s\n",
                to: .standardOutput,
            )
        }
        if let build = walls.build {
            try await terminal.write("  cold unit build: \(build)s\n", to: .standardOutput)
        }
        if let unitTest = walls.unitTest {
            try await terminal.write(
                "  unit \(unitWallLabel): \(unitTest)s\n",
                to: .standardOutput,
            )
        }
        if let snapshotBuild = walls.snapshotBuild {
            try await terminal.write(
                "  snapshot build (\(snapshotBuildLabel ?? "")): \(snapshotBuild)s\n",
                to: .standardOutput,
            )
        }
        if let snapshotTest = walls.snapshotTest {
            try await terminal.write(
                "  snapshot execution wall: \(snapshotTest)s\n",
                to: .standardOutput,
            )
        }
        try await terminal.write("\n", to: .standardOutput)
    }

    private func printSection(_ title: String) async throws {
        try await terminal.write("\n\(Self.separator)\n", to: .standardOutput)
        try await terminal.write("\(title)\n", to: .standardOutput)
        try await terminal.write("\(Self.separator)\n", to: .standardOutput)
    }

    private func printFailure(_ message: String, logURL: URL, tailLines: Int) async throws {
        try await terminal.write(
            "error: \(message). Tail of \(logURL.path):\n",
            to: .standardError,
        )
        do {
            let tail = try xcodeWorkspace.logTail(at: logURL, lines: tailLines)
            if tail.isEmpty == false {
                try await terminal.write(tail + "\n", to: .standardError)
            }
        } catch {
            try await terminal.write(
                "warning: could not read \(logURL.path): \(error)\n",
                to: .standardError,
            )
        }
    }

    private func runForwarding(_ invocation: CommandInvocation) async throws -> CommandResult {
        try await runner.run(
            invocation,
            outputHandler: { stream, bytes in
                try await terminal.write(
                    bytes,
                    to: stream == .standardOutput ? .standardOutput : .standardError,
                )
            },
        )
    }

    private func elapsedSeconds(since start: TimeInterval) async -> Int {
        await max(0, Int(clock.now() - start))
    }

    private func resolveUserPath(_ path: String) -> URL {
        path.hasPrefix("/")
            ? URL(filePath: path)
            : URL(filePath: path, relativeTo: repository).standardizedFileURL
    }
}
