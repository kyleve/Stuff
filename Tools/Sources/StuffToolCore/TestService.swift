import CryptoKit
import Foundation

public enum TestArchitectureMode: Equatable, Sendable {
    case run
    case only
    case skip
}

public struct TestRequest: Equatable, Sendable {
    public let scope: TestScope
    public let bundles: [String]
    public let only: [String]
    public let onlyFile: String?
    public let baseReference: String
    public let architectureMode: TestArchitectureMode
    public let artifactMode: TestArtifactMode
    public let build: Bool
    public let generate: Bool
    public let record: String?
    public let device: String
    public let os: String
    public let sharedSimulator: Bool
    public let timings: Bool
    public let review: Bool
    public let heartbeat: TimeInterval
    public let statusFile: String?

    public init(
        scope: TestScope,
        bundles: [String],
        only: [String],
        onlyFile: String?,
        baseReference: String,
        architectureMode: TestArchitectureMode,
        artifactMode: TestArtifactMode,
        build: Bool,
        generate: Bool,
        record: String?,
        device: String,
        os: String,
        sharedSimulator: Bool,
        timings: Bool,
        review: Bool,
        heartbeat: TimeInterval,
        statusFile: String?,
    ) {
        self.scope = scope
        self.bundles = bundles
        self.only = only
        self.onlyFile = onlyFile
        self.baseReference = baseReference
        self.architectureMode = architectureMode
        self.artifactMode = artifactMode
        self.build = build
        self.generate = generate
        self.record = record
        self.device = device
        self.os = os
        self.sharedSimulator = sharedSimulator
        self.timings = timings
        self.review = review
        self.heartbeat = heartbeat
        self.statusFile = statusFile
    }
}

/// Owns the complete host-side orchestration behind the public `./test` command.
public struct TestService: Sendable {
    private static let workspace = "Stuff.xcworkspace"
    private static let separator = String(repeating: "=", count: 60)

    private let runner: any CommandRunning
    private let simulator: any SimulatorResolving
    private let fileSystem: any FileSystem
    private let clock: any ToolClock
    private let terminal: any Terminal
    private let repository: URL
    private let temporaryDirectory: URL
    private let environment: [String: String]
    private let xcodeWorkspace: XcodeWorkspace
    private let architectureChecks: ArchitectureCheckService
    private let testArtifacts: TestArtifactService

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
        architectureChecks = ArchitectureCheckService(
            runner: runner,
            terminal: terminal,
            repository: repository,
            environment: environment,
        )
        testArtifacts = TestArtifactService(
            runner: runner,
            terminal: terminal,
            repository: repository,
        )
    }

    public func run(_ request: TestRequest) async throws -> Int32 {
        var only = request.only
        let onlyFileURL = request.onlyFile.map(resolveUserPath)
        if let onlyFileURL {
            guard try fileSystem.kind(of: onlyFileURL) == .file else {
                throw ToolFailure.message(
                    "--only-file does not exist: \(request.onlyFile ?? onlyFileURL.path)",
                )
            }
            try only += lines(in: String(decoding: fileSystem.read(onlyFileURL), as: UTF8.self))
            guard only.isEmpty == false else {
                throw ToolFailure.message(
                    "--only-file contains no test identifiers: " +
                        "\(request.onlyFile ?? onlyFileURL.path)",
                )
            }
        }

        if request.architectureMode != .skip {
            let status = try await architectureChecks.run()
            guard status == 0 else { throw ToolFailure.exitCode(status) }
        }
        if request.architectureMode == .only {
            return 0
        }

        if request.scope == .changed, request.artifactMode == .local {
            try await runBackupUpgrader()
        }

        let workDirectory = try makeWorkDirectory()
        var bundles = request.bundles
        var changedPaths: [String] = []
        if request.scope == .changed {
            changedPaths = try await self.changedPaths(comparedWith: request.baseReference)
            guard changedPaths.isEmpty == false else {
                try await terminal.write(
                    "==> No changes against \(request.baseReference) — nothing to test.\n",
                    to: .standardOutput,
                )
                return 0
            }
        }

        let fileUsesExplicitScheme = onlyFileURL != nil && request.only.isEmpty &&
            (request.scope == .all || request.scope == .snapshots)
        let needsGraph = request.scope == .changed || request.scope == .bundles ||
            request.scope == .only || (only.isEmpty == false && fileUsesExplicitScheme == false)
        let graph = needsGraph ? try await loadRepositoryGraph(in: workDirectory) : nil
        if request.scope == .changed {
            guard let graph else {
                throw ToolFailure.message("could not load the repository graph")
            }
            bundles = graph.affectedBundles(changedPaths: changedPaths)
            guard bundles.isEmpty == false else {
                try await terminal.write(
                    "==> No test bundle covers these changes:\n",
                    to: .standardOutput,
                )
                for path in changedPaths {
                    try await terminal.write("      \(path)\n", to: .standardOutput)
                }
                return 0
            }
            try await terminal.write(
                "==> Affected bundles: \(bundles.joined(separator: " "))\n",
                to: .standardOutput,
            )
        }

        var plan: TestRunPlan
        do {
            plan = try TestRunPlan(
                scope: request.scope,
                bundles: bundles,
                only: fileUsesExplicitScheme ? [] : only,
                graph: graph,
            )
            if let onlyFileURL {
                plan = try plan.filtering(usingFile: onlyFileURL.path)
            }
        } catch let failure as TestRunPlanFailure {
            throw ToolFailure.message(failure.description)
        }
        if request.scope != .changed, plan.runsUnitTests, request.artifactMode == .local {
            try await runBackupUpgrader()
        }
        if request.generate {
            let started = await clock.now()
            let status: Int32
            do {
                status = try await generateProject(in: workDirectory)
            } catch {
                try await emitPhaseTiming(
                    "generate",
                    started: started,
                    scheme: nil,
                    status: exitStatus(for: error),
                )
                throw error
            }
            try await emitPhaseTiming(
                "generate",
                started: started,
                scheme: nil,
                status: status,
            )
            guard status == 0 else { throw ToolFailure.exitCode(status) }
        }

        let artifactRoot: URL?
        let artifactPaths: TestArtifactPaths?
        switch request.artifactMode {
            case .local:
                artifactRoot = nil
                artifactPaths = nil
            case let .build(directory):
                let root = resolveUserPath(directory)
                try fileSystem.createDirectory(at: root, withIntermediateDirectories: true)
                artifactRoot = root.resolvingSymlinksInPath()
                artifactPaths = nil
            case let .test(directory, _):
                let root = resolveUserPath(directory)
                artifactRoot = root
                artifactPaths = try await testArtifacts.resolve(
                    root: root,
                    schemes: plan.schemes.map(\.name),
                )
                try await terminal.write(
                    "Validated test artifacts before simulator boot.\n",
                    to: .standardOutput,
                )
        }

        let destination: String
        if case .build = request.artifactMode {
            destination = "generic/platform=iOS Simulator"
        } else {
            let started = await clock.now()
            do {
                let udid = try await simulator.resolve(
                    device: request.device,
                    os: request.os,
                    shared: request.sharedSimulator,
                )
                try await emitPhaseTiming(
                    "simulator",
                    started: started,
                    scheme: nil,
                    status: 0,
                )
                destination = "platform=iOS Simulator,id=\(udid)"
            } catch {
                try await emitPhaseTiming(
                    "simulator",
                    started: started,
                    scheme: nil,
                    status: exitStatus(for: error),
                )
                throw error
            }
        }

        var runEnvironment = snapshotEnvironment(for: request)
        let productsDirectory: String? = switch request.artifactMode {
            case .local:
                try await builtProductsDirectory(
                    scheme: plan.schemes[0].name,
                    destination: destination,
                )
            case .build:
                nil
            case .test:
                artifactPaths?.products
        }
        if let productsDirectory {
            runEnvironment["TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH"] = productsDirectory
        } else {
            if case .build = request.artifactMode {
                // Build-only runs do not launch a test process that needs this path.
            } else {
                try await terminal.write(
                    "warning: could not resolve BUILT_PRODUCTS_DIR; package resource " +
                        "bundle lookups will fall back to the linker's placement\n",
                    to: .standardError,
                )
            }
        }

        var overallStatus: Int32 = 0
        var resultBundles: [URL] = []
        var logs: [URL] = []
        for scheme in plan.schemes {
            let logURL = workDirectory.appending(path: "\(scheme.name).log")
            let resultURL = workDirectory.appending(
                path: "\(scheme.name).xcresult",
                directoryHint: .isDirectory,
            )
            if try fileSystem.kind(of: resultURL) != .missing {
                try fileSystem.removeItem(at: resultURL)
            }
            if request.build {
                let started = await clock.now()
                let status: Int32
                do {
                    status = try await build(
                        scheme: scheme.name,
                        destination: destination,
                        workDirectory: workDirectory,
                        artifactRoot: artifactRoot,
                    )
                } catch {
                    try await emitPhaseTiming(
                        "build",
                        started: started,
                        scheme: scheme.name,
                        status: exitStatus(for: error),
                    )
                    throw error
                }
                try await emitPhaseTiming(
                    "build",
                    started: started,
                    scheme: scheme.name,
                    status: status,
                )
                guard status == 0 else { throw ToolFailure.exitCode(status) }
            }

            if case .build = request.artifactMode { continue }

            let testLocation: [String]
            if case .test = request.artifactMode {
                guard let path = artifactPaths?.schemes[scheme.name] else {
                    throw ToolFailure.message(
                        "test artifact manifest has no scheme named \(scheme.name)",
                    )
                }
                testLocation = ["-xctestrun", path]
            } else {
                testLocation = ["-workspace", Self.workspace, "-scheme", scheme.name]
            }

            if case let .test(_, enumerateSuites?) = request.artifactMode {
                let rawEnumeration = workDirectory.appending(
                    path: "\(scheme.name)-enumeration.json",
                )
                let logURL = workDirectory.appending(
                    path: "\(scheme.name)-enumeration.log",
                )
                let started = await clock.now()
                let result: CommandResult
                do {
                    result = try await xcodeWorkspace.xcodebuild(
                        ["test-without-building"] + testLocation + [
                            "-destination",
                            destination,
                            "-enumerate-tests",
                            "-test-enumeration-style",
                            "hierarchical",
                            "-test-enumeration-format",
                            "json",
                            "-test-enumeration-output-path",
                            rawEnumeration.path,
                        ],
                        environment: [:],
                        logURL: logURL,
                    )
                } catch {
                    try await emitPhaseTiming(
                        "enumerate",
                        started: started,
                        scheme: scheme.name,
                        status: exitStatus(for: error),
                    )
                    throw error
                }
                try await emitPhaseTiming(
                    "enumerate",
                    started: started,
                    scheme: scheme.name,
                    status: result.exitCode,
                )
                guard result.succeeded else {
                    try await printLogFailure(
                        "test enumeration failed for \(scheme.name)",
                        logURL: logURL,
                        tailLines: 30,
                    )
                    throw ToolFailure.exitCode(result.exitCode)
                }
                let status = try await testArtifacts.writeSuites(
                    input: rawEnumeration,
                    output: resolveUserPath(enumerateSuites),
                )
                guard status == 0 else { throw ToolFailure.exitCode(status) }
                return 0
            }

            let countsURL = workDirectory.appending(
                path: "counts-\(scheme.name)-\(scopeHash(scheme)).json",
            )
            let statusURL = request.statusFile.map(resolveUserPath)
            try await terminal.write(
                "==> Testing \(scheme.name) on \(request.device) / iOS \(request.os)\n",
                to: .standardOutput,
            )
            let reporter = try TestProgressReporter(
                scheme: scheme.name,
                heartbeat: request.heartbeat,
                statusURL: statusURL,
                countsURL: countsURL,
                logURL: logURL,
                countImages: request.timings,
                terminal: terminal,
                fileSystem: fileSystem,
                clock: clock,
            )
            try await reporter.start()
            let started = await clock.now()
            let result: CommandResult
            do {
                result = try await runner.run(
                    CommandInvocation(
                        executable: "xcodebuild",
                        arguments: ["test-without-building"] + testLocation + [
                            "-destination",
                            destination,
                            "-resultBundlePath",
                            resultURL.path,
                            "-collect-test-diagnostics",
                            "never",
                        ] + scheme.filters,
                        environment: runEnvironment,
                        workingDirectory: repository,
                        standardInput: [],
                        output: .merged,
                    ),
                    outputHandler: { stream, bytes in
                        try await reporter.consume(stream, bytes: bytes)
                    },
                )
            } catch {
                _ = try? await reporter.finish()
                try await emitPhaseTiming(
                    "test",
                    started: started,
                    scheme: scheme.name,
                    status: exitStatus(for: error),
                )
                throw error
            }
            let summary = try await reporter.finish()
            try await emitPhaseTiming(
                "test",
                started: started,
                scheme: scheme.name,
                status: result.exitCode,
            )
            resultBundles.append(resultURL)
            logs.append(logURL)
            if result.succeeded == false {
                overallStatus = result.exitCode
            }
            if summary.matchedTests == false, overallStatus == 0 {
                overallStatus = 1
            }
        }

        if case .build = request.artifactMode {
            guard let artifactRoot else {
                throw ToolFailure.message("test artifact build directory is missing")
            }
            let status = try await testArtifacts.create(
                root: artifactRoot,
                schemes: plan.schemes.map(\.name),
            )
            guard status == 0 else { throw ToolFailure.exitCode(status) }
            let bytes = try await testArtifacts.productBytes(root: artifactRoot)
            try await terminal.write(
                "CI_ARTIFACT {\"bytes\":\(bytes),\"schemes\":\(plan.schemes.count)}\n",
                to: .standardOutput,
            )
            return 0
        }

        if overallStatus != 0 {
            try await printFailures(resultBundles: resultBundles)
        }
        try await printSnapshotReports(request: request, logs: logs)

        try await terminal.write("\n", to: .standardOutput)
        if overallStatus == 0 {
            try await terminal.write(
                "==> Passed. Logs and result bundles: \(workDirectory.path)\n",
                to: .standardOutput,
            )
        } else {
            try await terminal.write(
                "==> Failed (exit \(overallStatus)). Logs and result bundles: " +
                    "\(workDirectory.path)\n",
                to: .standardOutput,
            )
        }
        return overallStatus
    }

    private func runBackupUpgrader() async throws {
        try await terminal.write("==> Testing backup upgrader\n", to: .standardOutput)
        let result = try await runForwarding(
            CommandInvocation(
                executable: "mise",
                arguments: [
                    "exec",
                    "--",
                    "ruby",
                    "Where/Tools/Tests/upgrade_backup_test.rb",
                ],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .streamed,
            ),
        )
        guard result.succeeded else {
            throw ToolFailure.exitCode(result.exitCode)
        }
    }

    private func makeWorkDirectory() throws -> URL {
        let canonicalRepository = repository.resolvingSymlinksInPath()
        let digest = SHA256.hash(data: Data(canonicalRepository.path.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        let configuredDirectory = environment["TEST_WORKDIR"].flatMap { path in
            path.isEmpty ? nil : resolveUserPath(path)
        }
        let directory = configuredDirectory ?? temporaryDirectory
            .appending(path: "where-test-\(digest)", directoryHint: .isDirectory)
        try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileSystem.setPosixPermissions(0o700, at: directory)
        return directory
    }

    private func changedPaths(comparedWith baseReference: String) async throws -> [String] {
        let referenceResult = try await runner.run(
            CommandInvocation(
                executable: "git",
                arguments: ["rev-parse", "--verify", "--quiet", baseReference],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
        )
        let base: String
        if referenceResult.succeeded {
            let mergeBase = try await runner.run(
                CommandInvocation(
                    executable: "git",
                    arguments: ["merge-base", "HEAD", baseReference],
                    environment: [:],
                    workingDirectory: repository,
                    standardInput: [],
                    output: .captured,
                ),
            )
            guard mergeBase.succeeded else {
                throw ToolFailure.message(
                    "git merge-base failed for '\(baseReference)': " +
                        mergeBase.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines),
                )
            }
            base = mergeBase.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            try await terminal.write(
                "warning: '\(baseReference)' not found; using uncommitted changes only\n",
                to: .standardError,
            )
            base = "HEAD"
        }
        let commands = [
            ["diff", "--name-only", base],
            ["diff", "--name-only"],
            ["ls-files", "--others", "--exclude-standard"],
        ]
        var paths: Set<String> = []
        for arguments in commands {
            let result = try await runner.run(
                CommandInvocation(
                    executable: "git",
                    arguments: arguments,
                    environment: [:],
                    workingDirectory: repository,
                    standardInput: [],
                    output: .captured,
                ),
            )
            guard result.succeeded else {
                throw ToolFailure.message(
                    "git \(arguments.joined(separator: " ")) failed: " +
                        result.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines),
                )
            }
            paths.formUnion(lines(in: result.standardOutputText))
        }
        return paths.sorted()
    }

    private func loadRepositoryGraph(in workDirectory: URL) async throws -> RepositoryGraph {
        let graphDirectory = workDirectory.appending(
            path: "tuist-graph",
            directoryHint: .isDirectory,
        )
        if try fileSystem.kind(of: graphDirectory) != .missing {
            try fileSystem.removeItem(at: graphDirectory)
        }
        try fileSystem.createDirectory(
            at: graphDirectory,
            withIntermediateDirectories: true,
        )
        let graphResult = try await runner.run(
            CommandInvocation(
                executable: "mise",
                arguments: [
                    "exec",
                    "--",
                    "tuist",
                    "graph",
                    "--format",
                    "json",
                    "--no-open",
                    "--output-path",
                    graphDirectory.path,
                ],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
        )
        guard graphResult.succeeded else {
            throw ToolFailure.message(
                "tuist graph failed: " + graphResult.standardErrorText
                    .trimmingCharacters(in: .whitespacesAndNewlines),
            )
        }
        let packageResult = try await runner.run(
            CommandInvocation(
                executable: "xcrun",
                arguments: ["swift", "package", "dump-package"],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
        )
        guard packageResult.succeeded else {
            throw ToolFailure.message(
                "swift package dump-package failed: " + packageResult.standardErrorText
                    .trimmingCharacters(in: .whitespacesAndNewlines),
            )
        }
        do {
            return try RepositoryGraph(
                tuistGraphData: fileSystem.read(graphDirectory.appending(path: "graph.json")),
                packageDumpData: Data(packageResult.standardOutput),
                repository: repository,
            )
        } catch {
            throw ToolFailure.message("could not read the Tuist graph: \(error)")
        }
    }

    private func generateProject(in workDirectory: URL) async throws -> Int32 {
        try await terminal.write(
            "==> Regenerating project (tuist generate --no-open)\n",
            to: .standardOutput,
        )
        let logURL = workDirectory.appending(path: "generate.log")
        let result = try await xcodeWorkspace.generateProject(
            logURL: logURL,
            outputHandler: nil,
        )
        if result.succeeded == false {
            try await printLogFailure(
                "tuist generate failed",
                logURL: logURL,
                tailLines: 20,
            )
        }
        return result.exitCode
    }

    private func builtProductsDirectory(
        scheme: String,
        destination: String,
    ) async throws -> String? {
        try await xcodeWorkspace.builtProductsDirectory(
            scheme: scheme,
            destination: destination,
            derivedData: nil,
        )
    }

    private func build(
        scheme: String,
        destination: String,
        workDirectory: URL,
        artifactRoot: URL?,
    ) async throws -> Int32 {
        try await terminal.write("==> Building \(scheme) for testing\n", to: .standardOutput)
        let logURL = workDirectory.appending(path: "\(scheme)-build.log")
        var arguments = [
            "build-for-testing",
            "-workspace",
            Self.workspace,
            "-scheme",
            scheme,
            "-configuration",
            "Debug",
            "-destination",
            destination,
        ]
        if let artifactRoot {
            arguments += [
                "-derivedDataPath",
                artifactRoot.appending(path: "DerivedData", directoryHint: .isDirectory).path,
                "ARCHS=arm64",
                "ONLY_ACTIVE_ARCH=YES",
            ]
        }
        let result = try await xcodeWorkspace.xcodebuild(
            arguments,
            environment: [:],
            logURL: logURL,
        )
        if result.succeeded == false {
            try await printLogFailure(
                "build failed for \(scheme)",
                logURL: logURL,
                tailLines: 30,
            )
        }
        return result.exitCode
    }

    private func emitPhaseTiming(
        _ phase: String,
        started: TimeInterval,
        scheme: String?,
        status: Int32,
    ) async throws {
        let elapsed = await (clock.now()) - started
        var payload: [String: Any] = [
            "phase": phase,
            "seconds": (elapsed * 1000).rounded() / 1000,
            "status": status,
        ]
        if let scheme { payload["scheme"] = scheme }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try await terminal.write(
            "CI_TIMING \(String(decoding: data, as: UTF8.self))\n",
            to: .standardOutput,
        )
    }

    private func exitStatus(for error: any Error) -> Int32 {
        switch error {
            case let failure as ToolFailure: failure.exitStatus
            case let failure as CommandLaunchFailure: failure.exitStatus
            default: 1
        }
    }

    private func snapshotEnvironment(for request: TestRequest) -> [String: String] {
        var result: [String: String] = [:]
        if let record = request.record {
            result["TEST_RUNNER_SNAPSHOT_RECORD"] = record
        }
        if request.timings {
            result["TEST_RUNNER_SNAPSHOT_TIMING"] = "1"
        }
        if request.review {
            result["TEST_RUNNER_SNAPSHOT_DIFF"] = "1"
        }
        if let multiplier = environment["SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER"],
           multiplier.isEmpty == false
        {
            result["TEST_RUNNER_SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER"] = multiplier
        }
        return result
    }

    private func scopeHash(_ scheme: TestSchemePlan) -> String {
        let input = ([scheme.name] + scheme.filters).joined(separator: "\n") + "\n"
        return Insecure.SHA1.hash(data: Data(input.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func printFailures(resultBundles: [URL]) async throws {
        try await printSection("FAILURES")
        let resultTool = XCResultTool(runner: runner, repository: repository)
        for resultURL in resultBundles where try fileSystem.kind(of: resultURL) == .directory {
            let catalog: XCResultTestCatalog
            do {
                catalog = try await resultTool.testCatalog(at: resultURL)
            } catch {
                try await terminal.write(
                    "warning: could not inspect \(resultURL.path): \(error)\n",
                    to: .standardError,
                )
                continue
            }
            let failures = catalog.failures
            for failure in failures {
                try await terminal.write("  \(failure.label)\n", to: .standardOutput)
                try await terminal.write(
                    "      ./test --only '\(failure.rerunIdentifier)'\n",
                    to: .standardOutput,
                )
            }
            if failures.isEmpty == false {
                try await terminal.write(
                    "\n  Result bundle: \(resultURL.path)\n",
                    to: .standardOutput,
                )
            }
        }
    }

    private func printSnapshotReports(request: TestRequest, logs: [URL]) async throws {
        guard request.timings || request.review else { return }
        var data: [Data] = []
        for log in logs {
            do {
                try data.append(fileSystem.read(log))
            } catch {
                try await terminal.write(
                    "warning: could not read snapshot report log \(log.path): \(error)\n",
                    to: .standardError,
                )
            }
        }
        let report: SnapshotLogReport
        do {
            report = try SnapshotLogReport(logs: data)
        } catch {
            try await terminal.write(
                "warning: could not build snapshot detail report: \(error)\n",
                to: .standardError,
            )
            return
        }
        if request.timings {
            try await printSection("SNAPSHOT CAPTURE PHASES")
            try await terminal.write(report.timingText(), to: .standardOutput)
        }
        if request.review {
            try await printSection("SNAPSHOT DIFFERENCES")
            try await terminal.write(
                report.differenceText(
                    isRecording: request.record != nil && request.record != "never",
                ),
                to: .standardOutput,
            )
        }
    }

    private func printSection(_ title: String) async throws {
        try await terminal.write("\n\(Self.separator)\n", to: .standardOutput)
        try await terminal.write("\(title)\n", to: .standardOutput)
        try await terminal.write("\(Self.separator)\n", to: .standardOutput)
    }

    private func printLogFailure(
        _ message: String,
        logURL: URL,
        tailLines: Int,
    ) async throws {
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
                let target: TerminalStream = stream == .standardOutput
                    ? .standardOutput
                    : .standardError
                try await terminal.write(bytes, to: target)
            },
        )
    }

    private func lines(in text: String) -> [String] {
        text.split(whereSeparator: \Character.isNewline).map(String.init)
    }

    private func resolveUserPath(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        return URL(filePath: path, relativeTo: repository).standardizedFileURL
    }
}
