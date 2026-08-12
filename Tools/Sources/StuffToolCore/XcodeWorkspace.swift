import CryptoKit
import Foundation

/// Shared mechanics for commands that generate and exercise the Xcode workspace.
struct XcodeWorkspace {
    private let fileSystem: any FileSystem
    private let repository: URL
    private let runner: any CommandRunning
    private let workspace: String

    init(
        runner: any CommandRunning,
        fileSystem: any FileSystem,
        repository: URL,
        workspace: String,
    ) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.repository = repository
        self.workspace = workspace
    }

    var checkoutIdentifier: String {
        let path = repository.resolvingSymlinksInPath().standardizedFileURL.path
        return SHA256.hash(data: Data(path.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func generateProject(
        logURL: URL,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        try await runLogged(
            CommandInvocation(
                executable: "mise",
                arguments: ["exec", "--", "tuist", "generate", "--no-open"],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .streamed,
            ),
            logURL: logURL,
            outputHandler: outputHandler,
        )
    }

    func xcodebuild(
        _ arguments: [String],
        environment: [String: String],
        logURL: URL,
    ) async throws -> CommandResult {
        try await runLogged(
            CommandInvocation(
                executable: "xcodebuild",
                arguments: arguments,
                environment: environment,
                workingDirectory: repository,
                standardInput: [],
                output: .merged,
            ),
            logURL: logURL,
            outputHandler: nil,
        )
    }

    func builtProductsDirectory(
        scheme: String,
        destination: String,
        derivedData: URL?,
    ) async throws -> String? {
        var arguments = [
            "-showBuildSettings",
            "-workspace",
            workspace,
            "-scheme",
            scheme,
            "-destination",
            destination,
        ]
        if let derivedData {
            arguments += ["-derivedDataPath", derivedData.path]
        }
        let result = try await runner.run(
            CommandInvocation(
                executable: "xcodebuild",
                arguments: arguments,
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
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

    func testCatalog(
        at resultBundle: URL,
        exportingTo output: URL,
    ) async throws -> XCResultTestCatalog {
        let data = try await resultTool.testsData(at: resultBundle)
        try fileSystem.write(data, to: output, atomically: false)
        return try JSONDecoder().decode(XCResultTestCatalog.self, from: data)
    }

    func summary(
        at resultBundle: URL,
        exportingTo output: URL,
    ) async throws -> XCResultSummary {
        let data = try await resultTool.summaryData(at: resultBundle)
        try fileSystem.write(data, to: output, atomically: false)
        return try JSONDecoder().decode(XCResultSummary.self, from: data)
    }

    func removeIfPresent(_ url: URL) throws {
        if fileSystem.kind(of: url) != .missing {
            try fileSystem.removeItem(at: url)
        }
    }

    func logTail(at url: URL, lines count: Int) throws -> String {
        try String(decoding: fileSystem.read(url), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(count)
            .joined(separator: "\n")
    }

    private var resultTool: XCResultTool {
        XCResultTool(runner: runner, repository: repository)
    }

    private func runLogged(
        _ invocation: CommandInvocation,
        logURL: URL,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        try await LoggedCommandRunner(runner: runner, fileSystem: fileSystem)
            .run(invocation, logURL: logURL, outputHandler: outputHandler)
    }
}
