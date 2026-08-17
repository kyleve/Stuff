import Foundation

/// Chooses whether a test invocation uses the local workspace or portable CI artifacts.
public enum TestArtifactMode: Equatable, Sendable {
    case local
    case build(directory: String)
    case test(directory: String, enumerateSuites: String?)
}

struct TestArtifactPaths: Decodable, Equatable {
    let products: String
    let schemes: [String: String]
}

/// Bridges `./test` orchestration to the directly tested portable-artifact Python module.
struct TestArtifactService {
    private let runner: any CommandRunning
    private let terminal: any Terminal
    private let repository: URL

    init(
        runner: any CommandRunning,
        terminal: any Terminal,
        repository: URL,
    ) {
        self.runner = runner
        self.terminal = terminal
        self.repository = repository
    }

    func resolve(root: URL, schemes: [String]) async throws -> TestArtifactPaths {
        let result = try await runner.run(
            invocation(
                arguments: ["resolve-all", "--root", root.path] +
                    schemes.flatMap { ["--scheme", $0] },
                output: .captured,
            ),
        )
        guard result.succeeded else {
            try await report(result)
            throw ToolFailure.exitCode(result.exitCode)
        }
        if result.standardError.isEmpty == false {
            try await terminal.write(result.standardError, to: .standardError)
        }
        do {
            return try JSONDecoder().decode(
                TestArtifactPaths.self,
                from: Data(result.standardOutput),
            )
        } catch {
            throw ToolFailure.message("could not decode test artifact paths: \(error)")
        }
    }

    func create(root: URL, schemes: [String]) async throws -> Int32 {
        let result = try await runForwarding(
            invocation(
                arguments: ["create", "--root", root.path] +
                    schemes.flatMap { ["--scheme", $0] },
                output: .streamed,
            ),
        )
        return result.exitCode
    }

    func writeSuites(input: URL, output: URL) async throws -> Int32 {
        let result = try await runForwarding(
            invocation(
                arguments: [
                    "suites",
                    "--input",
                    input.path,
                    "--output",
                    output.path,
                ],
                output: .streamed,
            ),
        )
        return result.exitCode
    }

    func productBytes(root: URL) async throws -> Int64 {
        let products = root.appending(
            path: "DerivedData/Build/Products",
            directoryHint: .isDirectory,
        )
        let result = try await runner.run(
            CommandInvocation(
                executable: "du",
                arguments: ["-sk", products.path],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
        )
        guard result.succeeded else {
            try await report(result)
            throw ToolFailure.exitCode(result.exitCode)
        }
        guard let kibibytes = result.standardOutputText
            .split(whereSeparator: \Character.isWhitespace)
            .first.flatMap({ Int64($0) })
        else {
            throw ToolFailure.message("could not parse test artifact size")
        }
        return kibibytes * 1024
    }

    private func invocation(
        arguments: [String],
        output: CommandOutputMode,
    ) -> CommandInvocation {
        CommandInvocation(
            executable: "python3",
            arguments: [".circleci/test_artifacts.py"] + arguments,
            environment: [:],
            workingDirectory: repository,
            standardInput: [],
            output: output,
        )
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

    private func report(_ result: CommandResult) async throws {
        if result.standardOutput.isEmpty == false {
            try await terminal.write(result.standardOutput, to: .standardOutput)
        }
        if result.standardError.isEmpty == false {
            try await terminal.write(result.standardError, to: .standardError)
        }
    }
}
