import CryptoKit
import Foundation

public struct TestRequest: Equatable, Sendable {
    public let scope: TestScope
    public let bundles: [String]
    public let only: [String]
    public let baseReference: String
    public let build: Bool
    public let generate: Bool
    public let record: String?
    public let device: String
    public let os: String
    public let sharedSimulator: Bool
    public let snapshotShard: String?
    public let timings: Bool
    public let review: Bool
    public let heartbeat: TimeInterval
    public let statusFile: String?
    public let timingReport: String?

    public init(
        scope: TestScope,
        bundles: [String] = [],
        only: [String] = [],
        baseReference: String = "origin/main",
        build: Bool = true,
        generate: Bool = true,
        record: String? = nil,
        device: String = "iPhone 17",
        os: String = "27.0",
        sharedSimulator: Bool = false,
        snapshotShard: String? = nil,
        timings: Bool = false,
        review: Bool = false,
        heartbeat: TimeInterval = 15,
        statusFile: String? = nil,
        timingReport: String? = nil,
    ) {
        self.scope = scope
        self.bundles = bundles
        self.only = only
        self.baseReference = baseReference
        self.build = build
        self.generate = generate
        self.record = record
        self.device = device
        self.os = os
        self.sharedSimulator = sharedSimulator
        self.snapshotShard = snapshotShard
        self.timings = timings
        self.review = review
        self.heartbeat = heartbeat
        self.statusFile = statusFile
        self.timingReport = timingReport
    }
}

public enum TestServiceFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)
    case exitCode(Int32)
    case reported

    public var description: String {
        switch self {
            case let .message(message): message
            case let .exitCode(code): "test prerequisite exited with status \(code)"
            case .reported: "test command failed"
        }
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
    }

    public func run(_ request: TestRequest) async throws -> Int32 {
        try await terminal.write("==> Testing backup upgrader\n", to: .standardOutput)
        let backupResult = try await runForwarding(
            CommandInvocation(
                executable: "mise",
                arguments: [
                    "exec",
                    "--",
                    "ruby",
                    "Where/Tools/Tests/upgrade_backup_test.rb",
                ],
                workingDirectory: repository,
                captureOutput: false,
            ),
        )
        guard backupResult.succeeded else {
            throw TestServiceFailure.exitCode(backupResult.exitCode)
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

        let needsGraph = request.scope == .changed || request.scope == .bundles ||
            request.scope == .only || request.only.isEmpty == false
        let graph = needsGraph ? try await loadRepositoryGraph(in: workDirectory) : nil
        if request.scope == .changed {
            guard let graph else {
                throw TestServiceFailure.message("could not load the repository graph")
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

        let shardIdentifiers = try await snapshotShardIdentifiers(request.snapshotShard)
        let plan: TestRunPlan
        do {
            plan = try TestRunPlan(
                scope: request.scope,
                bundles: bundles,
                only: request.only,
                snapshotShardIdentifiers: shardIdentifiers,
                graph: graph,
            )
        } catch let failure as TestRunPlanFailure {
            throw TestServiceFailure.message(failure.description)
        }
        if request.timingReport != nil, plan.includesSnapshots == false {
            throw TestServiceFailure.message("--timing-report requires a snapshot test scope")
        }

        if request.generate {
            try await generateProject(in: workDirectory)
        }

        let udid = try await simulator.resolve(
            device: request.device,
            os: request.os,
            shared: request.sharedSimulator,
        )
        let destination = "platform=iOS Simulator,id=\(udid)"
        var runEnvironment = snapshotEnvironment(for: request)
        if let productsDirectory = try await builtProductsDirectory(
            scheme: plan.schemes[0].name,
            destination: destination,
        ) {
            runEnvironment["TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH"] = productsDirectory
        } else {
            try await terminal.write(
                "warning: could not resolve BUILT_PRODUCTS_DIR; package resource " +
                    "bundle lookups will fall back to the linker's placement\n",
                to: .standardError,
            )
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
            if fileSystem.kind(of: resultURL) != .missing {
                try fileSystem.removeItem(at: resultURL)
            }
            if request.build {
                try await build(
                    scheme: scheme.name,
                    destination: destination,
                    workDirectory: workDirectory,
                )
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
            let result: CommandResult
            do {
                result = try await runner.run(
                    CommandInvocation(
                        executable: "xcodebuild",
                        arguments: [
                            "test-without-building",
                            "-workspace",
                            Self.workspace,
                            "-scheme",
                            scheme.name,
                            "-destination",
                            destination,
                            "-resultBundlePath",
                            resultURL.path,
                            "-collect-test-diagnostics",
                            "never",
                        ] + scheme.filters,
                        environment: runEnvironment,
                        workingDirectory: repository,
                        captureOutput: false,
                        mergeStandardError: true,
                    ),
                    outputHandler: { stream, bytes in
                        try await reporter.consume(stream, bytes: bytes)
                    },
                )
            } catch {
                _ = try? await reporter.finish()
                throw error
            }
            let summary = try await reporter.finish()
            resultBundles.append(resultURL)
            logs.append(logURL)
            if result.succeeded == false {
                overallStatus = result.exitCode
            }
            if summary.matchedTests == false, overallStatus == 0 {
                overallStatus = 1
            }
        }

        if let reportPath = request.timingReport {
            overallStatus = try await writeTimingReport(
                to: resolveUserPath(reportPath),
                resultBundles: resultBundles,
                currentStatus: overallStatus,
            )
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
                workingDirectory: repository,
            ),
        )
        let base: String
        if referenceResult.succeeded {
            let mergeBase = try await runner.run(
                CommandInvocation(
                    executable: "git",
                    arguments: ["merge-base", "HEAD", baseReference],
                    workingDirectory: repository,
                ),
            )
            guard mergeBase.succeeded else {
                throw TestServiceFailure.message(
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
                    workingDirectory: repository,
                ),
            )
            guard result.succeeded else {
                throw TestServiceFailure.message(
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
        if fileSystem.kind(of: graphDirectory) != .missing {
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
                workingDirectory: repository,
            ),
        )
        guard graphResult.succeeded else {
            throw TestServiceFailure.message(
                "tuist graph failed: " + graphResult.standardErrorText
                    .trimmingCharacters(in: .whitespacesAndNewlines),
            )
        }
        let packageResult = try await runner.run(
            CommandInvocation(
                executable: "xcrun",
                arguments: ["swift", "package", "dump-package"],
                workingDirectory: repository,
            ),
        )
        guard packageResult.succeeded else {
            throw TestServiceFailure.message(
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
            throw TestServiceFailure.message("could not read the Tuist graph: \(error)")
        }
    }

    private func snapshotShardIdentifiers(_ shard: String?) async throws -> [String] {
        guard let shard else { return [] }
        let number = String(shard.prefix(while: { $0 != "/" }))
        let result = try await runner.run(
            CommandInvocation(
                executable: repository.appending(path: "snapshot-shards").path,
                arguments: ["list", number],
                workingDirectory: repository,
            ),
        )
        guard result.succeeded else {
            try await terminal.write(result.standardError, to: .standardError)
            throw TestServiceFailure.exitCode(result.exitCode)
        }
        return lines(in: result.standardOutputText)
    }

    private func generateProject(in workDirectory: URL) async throws {
        try await terminal.write(
            "==> Regenerating project (tuist generate --no-open)\n",
            to: .standardOutput,
        )
        let logURL = workDirectory.appending(path: "generate.log")
        let result = try await runLogged(
            CommandInvocation(
                executable: "mise",
                arguments: ["exec", "--", "tuist", "generate", "--no-open"],
                workingDirectory: repository,
                captureOutput: false,
                mergeStandardError: true,
            ),
            logURL: logURL,
        )
        guard result.succeeded else {
            try await printLogFailure(
                "tuist generate failed",
                logURL: logURL,
                tailLines: 20,
            )
            throw TestServiceFailure.reported
        }
    }

    private func builtProductsDirectory(
        scheme: String,
        destination: String,
    ) async throws -> String? {
        let result = try await runner.run(
            CommandInvocation(
                executable: "xcodebuild",
                arguments: [
                    "-showBuildSettings",
                    "-workspace",
                    Self.workspace,
                    "-scheme",
                    scheme,
                    "-destination",
                    destination,
                ],
                workingDirectory: repository,
            ),
        )
        guard result.succeeded else { return nil }
        let marker = " BUILT_PRODUCTS_DIR = "
        for line in result.standardOutputText.split(separator: "\n") {
            guard let range = line.range(of: marker) else { continue }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty == false { return value }
        }
        return nil
    }

    private func build(
        scheme: String,
        destination: String,
        workDirectory: URL,
    ) async throws {
        try await terminal.write("==> Building \(scheme) for testing\n", to: .standardOutput)
        let logURL = workDirectory.appending(path: "\(scheme)-build.log")
        let result = try await runLogged(
            CommandInvocation(
                executable: "xcodebuild",
                arguments: [
                    "build-for-testing",
                    "-workspace",
                    Self.workspace,
                    "-scheme",
                    scheme,
                    "-destination",
                    destination,
                ],
                workingDirectory: repository,
                captureOutput: false,
                mergeStandardError: true,
            ),
            logURL: logURL,
        )
        guard result.succeeded else {
            try await printLogFailure(
                "build failed for \(scheme)",
                logURL: logURL,
                tailLines: 30,
            )
            throw TestServiceFailure.reported
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
        return result
    }

    private func scopeHash(_ scheme: TestSchemePlan) -> String {
        let input = ([scheme.name] + scheme.filters).joined(separator: "\n") + "\n"
        return Insecure.SHA1.hash(data: Data(input.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func writeTimingReport(
        to output: URL,
        resultBundles: [URL],
        currentStatus: Int32,
    ) async throws -> Int32 {
        let available = resultBundles.filter { fileSystem.kind(of: $0) == .directory }
        guard available.isEmpty == false else {
            try await terminal.write(
                "error: no result bundle is available for --timing-report\n",
                to: .standardError,
            )
            return currentStatus == 0 ? 1 : currentStatus
        }
        let arguments = ["report"] + available.flatMap { ["--xcresult", $0.path] } + [
            "--output",
            output.path,
        ]
        let result = try await runForwarding(
            CommandInvocation(
                executable: repository.appending(path: "snapshot-shards").path,
                arguments: arguments,
                workingDirectory: repository,
                captureOutput: false,
            ),
        )
        return result.succeeded || currentStatus != 0 ? currentStatus : result.exitCode
    }

    private func printFailures(resultBundles: [URL]) async throws {
        try await printSection("FAILURES")
        let resultTool = XCResultTool(runner: runner, repository: repository)
        for resultURL in resultBundles where fileSystem.kind(of: resultURL) == .directory {
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
        let data: Data
        do {
            data = try fileSystem.read(logURL)
        } catch {
            try await terminal.write(
                "warning: could not read \(logURL.path): \(error)\n",
                to: .standardError,
            )
            return
        }
        let lines = String(decoding: data, as: UTF8.self).split(
            separator: "\n",
            omittingEmptySubsequences: false,
        )
        let tail = lines.suffix(tailLines).joined(separator: "\n")
        if tail.isEmpty == false {
            try await terminal.write(tail + "\n", to: .standardError)
        }
    }

    private func runLogged(
        _ invocation: CommandInvocation,
        logURL: URL,
    ) async throws -> CommandResult {
        try await LoggedCommandRunner(
            runner: runner,
            fileSystem: fileSystem,
        ).run(invocation, logURL: logURL)
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
