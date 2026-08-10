import Foundation

public struct FlakyRequest: Equatable, Sendable {
    public let suiteRuns: Int
    public let iterations: Int
    public let device: String
    public let os: String
    public let scheme: String
    public let relaunch: FlakyRelaunch
    public let updateReport: Bool
    public let top: Int?

    public init(
        suiteRuns: Int = 10,
        iterations: Int = 50,
        device: String = "iPhone 17",
        os: String = "27.0",
        scheme: String = "Stuff-iOS-Tests",
        relaunch: FlakyRelaunch = .yes,
        updateReport: Bool = true,
        top: Int? = nil,
    ) {
        self.suiteRuns = suiteRuns
        self.iterations = iterations
        self.device = device
        self.os = os
        self.scheme = scheme
        self.relaunch = relaunch
        self.updateReport = updateReport
        self.top = top
    }
}

public enum FlakyServiceFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)
    case exitCode(Int32)

    public var description: String {
        switch self {
            case let .message(message): message
            case let .exitCode(code): "flaky prerequisite exited with status \(code)"
        }
    }
}

/// Runs the report-only suite and isolated repetition phases behind `./flaky`.
public struct FlakyService: Sendable {
    private static let workspace = "Stuff.xcworkspace"
    private static let separator = String(repeating: "=", count: 60)

    private struct Paths {
        let work: URL
        let derived: URL
        let buildLog: URL
        let suiteDirectory: URL
        let tightDirectory: URL
        let suspects: URL
        let suiteCounts: URL
    }

    private let runner: any CommandRunning
    private let simulator: any SimulatorResolving
    private let fileSystem: any FileSystem
    private let clock: any ToolClock
    private let terminal: any Terminal
    private let repository: URL
    private let home: URL
    private let environment: [String: String]

    public init(
        runner: any CommandRunning,
        simulator: any SimulatorResolving,
        fileSystem: any FileSystem,
        clock: any ToolClock,
        terminal: any Terminal,
        repository: URL,
        home: URL,
        environment: [String: String],
    ) {
        self.runner = runner
        self.simulator = simulator
        self.fileSystem = fileSystem
        self.clock = clock
        self.terminal = terminal
        self.repository = repository
        self.home = home
        self.environment = environment
    }

    public func run(_ request: FlakyRequest) async throws -> Int32 {
        let udid = try await simulator.resolve(
            device: request.device,
            os: request.os,
            shared: false,
        )
        let destination = "platform=iOS Simulator,id=\(udid)"
        let paths = try makePaths()

        try await terminal.write(
            "==> Regenerating project (tuist generate --no-open)\n",
            to: .standardOutput,
        )
        let generation = try await runner.run(
            CommandInvocation(
                executable: "mise",
                arguments: ["exec", "--", "tuist", "generate", "--no-open"],
                workingDirectory: repository,
                captureOutput: false,
            ),
            outputHandler: { stream, bytes in
                if stream == .standardError {
                    try await terminal.write(bytes, to: .standardError)
                }
            },
        )
        guard generation.succeeded else {
            throw FlakyServiceFailure.exitCode(generation.exitCode)
        }

        var testEnvironment: [String: String] = [:]
        if let products = try await builtProductsDirectory(
            scheme: request.scheme,
            destination: destination,
            derivedData: paths.derived,
        ) {
            testEnvironment["TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH"] = products
        } else {
            try await terminal.write(
                "warning: could not resolve BUILT_PRODUCTS_DIR; package resource " +
                    "bundle lookups will fall back to the linker's placement\n",
                to: .standardError,
            )
        }

        try await terminal.write(
            "==> Building for testing (\(request.scheme)) on \(request.device) / " +
                "iOS \(request.os)\n",
            to: .standardOutput,
        )
        let build = try await runXcodebuild(
            arguments: [
                "build-for-testing",
                "-workspace",
                Self.workspace,
                "-scheme",
                request.scheme,
                "-destination",
                destination,
                "-derivedDataPath",
                paths.derived.path,
            ],
            environment: [:],
            logURL: paths.buildLog,
        )
        guard build.succeeded else {
            try await printFailure(build, logURL: paths.buildLog)
            throw FlakyServiceFailure.exitCode(build.exitCode)
        }

        try await terminal.write(
            "\n==> Phase 1: running the full suite \(request.suiteRuns) time(s)\n",
            to: .standardOutput,
        )
        var suiteCatalogs: [XCResultTestCatalog] = []
        for index in 1 ... request.suiteRuns {
            let resultBundle = paths.suiteDirectory.appending(
                path: "run_\(index).xcresult",
                directoryHint: .isDirectory,
            )
            let log = paths.suiteDirectory.appending(path: "run_\(index).log")
            let json = paths.suiteDirectory.appending(path: "run_\(index).json")
            try removeIfPresent(resultBundle)
            try await terminal.write(
                "  - suite run \(index)/\(request.suiteRuns)\n",
                to: .standardOutput,
            )
            _ = try await runXcodebuild(
                arguments: [
                    "test-without-building",
                    "-workspace",
                    Self.workspace,
                    "-scheme",
                    request.scheme,
                    "-destination",
                    destination,
                    "-derivedDataPath",
                    paths.derived.path,
                    "-resultBundlePath",
                    resultBundle.path,
                    "-collect-test-diagnostics",
                    "never",
                ],
                environment: testEnvironment,
                logURL: log,
            )
            if let catalog = try await readCatalog(
                resultBundle: resultBundle,
                output: json,
                log: log,
                context: "suite run \(index)",
            ) {
                suiteCatalogs.append(catalog)
            }
        }

        try await terminal.write("\n==> Analyzing suite runs\n", to: .standardOutput)
        let suite = FlakySuiteAnalysis(catalogs: suiteCatalogs)
        let suspectText = suite.suspects.isEmpty ? "" : suite.suspects.joined(separator: "\n") + "\n"
        try fileSystem.write(Data(suspectText.utf8), to: paths.suspects, atomically: false)
        try fileSystem.write(suite.encodedCounts(), to: paths.suiteCounts, atomically: false)
        try await terminal.write(
            "  \(suite.stats.count) distinct tests seen across the suite runs\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "  \(suite.suspects.count) suspect(s) failed at least once\n",
            to: .standardOutput,
        )

        var tightCounts: [String: FlakyTightCounts] = [:]
        if suite.suspects.isEmpty {
            try await terminal.write(
                "\n==> Phase 2: skipped (no suspects from phase 1)\n",
                to: .standardOutput,
            )
        } else {
            try await terminal.write(
                "\n==> Phase 2: tight-looping \(suite.suspects.count) suspect(s) " +
                    "\(request.iterations) time(s) each\n",
                to: .standardOutput,
            )
            for (offset, identifier) in suite.suspects.enumerated() {
                let index = offset + 1
                let stem = paths.tightDirectory.appending(path: "tight_\(index)")
                let resultBundle = URL(
                    filePath: stem.path + ".xcresult",
                    directoryHint: .isDirectory,
                )
                let log = URL(filePath: stem.path + ".log")
                let identifierFile = URL(filePath: stem.path + ".id")
                let testsJSON = URL(filePath: stem.path + ".tests.json")
                let summaryJSON = URL(filePath: stem.path + ".summary.json")
                try removeIfPresent(resultBundle)
                try await terminal.write(
                    "  - [\(index)/\(suite.suspects.count)] \(identifier)\n",
                    to: .standardOutput,
                )
                try fileSystem.write(
                    Data((identifier + "\n").utf8),
                    to: identifierFile,
                    atomically: false,
                )
                _ = try await runXcodebuild(
                    arguments: [
                        "test-without-building",
                        "-workspace",
                        Self.workspace,
                        "-scheme",
                        request.scheme,
                        "-destination",
                        destination,
                        "-derivedDataPath",
                        paths.derived.path,
                        "-only-testing:\(identifier)",
                        "-test-iterations",
                        String(request.iterations),
                        "-test-repetition-relaunch-enabled",
                        request.relaunch.rawValue,
                        "-resultBundlePath",
                        resultBundle.path,
                        "-collect-test-diagnostics",
                        "never",
                    ],
                    environment: testEnvironment,
                    logURL: log,
                )
                let catalog = try await readCatalog(
                    resultBundle: resultBundle,
                    output: testsJSON,
                    log: log,
                    context: "tight-loop run \(index)",
                )
                let summary = try await readSummary(
                    resultBundle: resultBundle,
                    output: summaryJSON,
                    log: log,
                    context: "tight-loop run \(index)",
                )
                tightCounts[identifier] = FlakySuiteAnalysis.tightCounts(
                    catalog: catalog,
                    summary: summary,
                )
            }
        }

        let report = FlakyReport(
            suite: suite,
            tightCounts: tightCounts,
            suiteRuns: request.suiteRuns,
        )
        try await terminal.write(
            "\n\(Self.separator)\nFLAKY TEST REPORT\n\(Self.separator)\n",
            to: .standardOutput,
        )
        try await terminal.write(report.consoleText(top: request.top), to: .standardOutput)

        if request.updateReport {
            let metadata = await FlakyReportMetadata(
                date: clock.date(),
                suiteRuns: request.suiteRuns,
                iterations: request.iterations,
                relaunch: request.relaunch.rawValue,
                device: request.device,
                os: request.os,
                top: request.top,
            )
            let reportURL = repository.appending(path: "FLAKY_TESTS.md")
            try fileSystem.write(
                Data(report.markdown(metadata).utf8),
                to: reportURL,
                atomically: true,
            )
            try await terminal.write("\nWrote FLAKY_TESTS.md\n", to: .standardOutput)
        }
        try await terminal.write(
            "\nLogs and result bundles: \(paths.work.path)\n",
            to: .standardOutput,
        )
        return 0
    }

    private func makePaths() throws -> Paths {
        let configured = environment["FLAKY_WORKDIR"].flatMap { path in
            path.isEmpty ? nil : resolveUserPath(path)
        }
        let work = configured ?? home
            .appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
            .appending(
                path: "where-flaky-\(repository.lastPathComponent)",
                directoryHint: .isDirectory,
            )
        let paths = Paths(
            work: work,
            derived: work.appending(path: "DerivedData", directoryHint: .isDirectory),
            buildLog: work.appending(path: "build.log"),
            suiteDirectory: work.appending(path: "suite", directoryHint: .isDirectory),
            tightDirectory: work.appending(path: "tight", directoryHint: .isDirectory),
            suspects: work.appending(path: "suspects.txt"),
            suiteCounts: work.appending(path: "suite_counts.json"),
        )
        try fileSystem.createDirectory(at: work, withIntermediateDirectories: true)
        for url in [paths.suiteDirectory, paths.tightDirectory, paths.suspects, paths.suiteCounts] {
            try removeIfPresent(url)
        }
        try fileSystem.createDirectory(
            at: paths.suiteDirectory,
            withIntermediateDirectories: true,
        )
        try fileSystem.createDirectory(
            at: paths.tightDirectory,
            withIntermediateDirectories: true,
        )
        return paths
    }

    private func runXcodebuild(
        arguments: [String],
        environment: [String: String],
        logURL: URL,
    ) async throws -> CommandResult {
        try await LoggedCommandRunner(runner: runner, fileSystem: fileSystem).run(
            CommandInvocation(
                executable: "xcodebuild",
                arguments: arguments,
                environment: environment,
                workingDirectory: repository,
                captureOutput: false,
                mergeStandardError: true,
            ),
            logURL: logURL,
        )
    }

    private func builtProductsDirectory(
        scheme: String,
        destination: String,
        derivedData: URL,
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
                    "-derivedDataPath",
                    derivedData.path,
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

    private func readCatalog(
        resultBundle: URL,
        output: URL,
        log: URL,
        context: String,
    ) async throws -> XCResultTestCatalog? {
        do {
            let data = try await XCResultTool(runner: runner, repository: repository)
                .testsData(at: resultBundle)
            try fileSystem.write(data, to: output, atomically: false)
            do {
                return try JSONDecoder().decode(XCResultTestCatalog.self, from: data)
            } catch {
                try await warnInspectionFailure(error, output: output, log: log, context: context)
            }
        } catch {
            try await warnInspectionFailure(error, output: output, log: log, context: context)
        }
        return nil
    }

    private func readSummary(
        resultBundle: URL,
        output: URL,
        log: URL,
        context: String,
    ) async throws -> XCResultSummary? {
        do {
            let data = try await XCResultTool(runner: runner, repository: repository)
                .summaryData(at: resultBundle)
            try fileSystem.write(data, to: output, atomically: false)
            do {
                return try JSONDecoder().decode(XCResultSummary.self, from: data)
            } catch {
                try await warnInspectionFailure(error, output: output, log: log, context: context)
            }
        } catch {
            try await warnInspectionFailure(error, output: output, log: log, context: context)
        }
        return nil
    }

    private func warnInspectionFailure(
        _ error: any Error,
        output: URL,
        log: URL,
        context: String,
    ) async throws {
        let message = "could not read results for \(context) (\(error))"
        try await terminal.write("  warning: \(message) (see \(log.path))\n", to: .standardError)
        let existing = (try? fileSystem.read(log)) ?? Data()
        var combined = existing
        combined.append(Data(("\nwarning: " + message + "\n").utf8))
        try fileSystem.write(combined, to: log, atomically: false)
        if fileSystem.kind(of: output) != .missing {
            try fileSystem.removeItem(at: output)
        }
    }

    private func printFailure(_ result: CommandResult, logURL: URL) async throws {
        try await terminal.write(
            "error: build failed (exit \(result.exitCode)). Tail of \(logURL.path):\n",
            to: .standardError,
        )
        do {
            let lines = try String(decoding: fileSystem.read(logURL), as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false)
            let tail = lines.suffix(40).joined(separator: "\n")
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

    private func removeIfPresent(_ url: URL) throws {
        if fileSystem.kind(of: url) != .missing {
            try fileSystem.removeItem(at: url)
        }
    }

    private func resolveUserPath(_ path: String) -> URL {
        path.hasPrefix("/")
            ? URL(filePath: path)
            : URL(filePath: path, relativeTo: repository).standardizedFileURL
    }
}
