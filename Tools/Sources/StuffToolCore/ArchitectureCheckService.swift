import Foundation

/// Runs the repository-owned Bumper Bowling validation sequence.
public struct ArchitectureCheckService: Sendable {
    private struct Check {
        let heading: String
        let arguments: [String]
    }

    private static let checks = [
        Check(
            heading: "Validating Bumper Bowling configuration",
            arguments: ["run", "bumper", "config", "."],
        ),
        Check(
            heading: "Testing Bumper Bowling rules",
            arguments: ["run", "bumper", "test", "."],
        ),
        Check(
            heading: "Enforcing Where architecture",
            arguments: ["run", "bumper", "lint", ".", "--timings"],
        ),
    ]

    private let runner: any CommandRunning
    private let terminal: any Terminal
    private let repository: URL
    private let environment: [String: String]

    public init(
        runner: any CommandRunning,
        terminal: any Terminal,
        repository: URL,
        environment: [String: String],
    ) {
        self.runner = runner
        self.terminal = terminal
        self.repository = repository
        self.environment = environment
    }

    public func run() async throws -> Int32 {
        let commandEnvironment = [
            "BUMPER_CACHE_DIR": nonemptyEnvironmentValue("BUMPER_CACHE_DIR")
                ?? ".build/bumper-cache",
            "BUMPER_RUNNER_BUILD_CONFIGURATION": nonemptyEnvironmentValue(
                "BUMPER_RUNNER_BUILD_CONFIGURATION",
            ) ?? "debug",
        ]

        for check in Self.checks {
            try await terminal.write("==> \(check.heading)\n", to: .standardOutput)
            let result = try await runner.run(
                CommandInvocation(
                    executable: "swift",
                    arguments: check.arguments,
                    environment: commandEnvironment,
                    workingDirectory: repository,
                    standardInput: [],
                    output: .streamed,
                ),
                outputHandler: { stream, bytes in
                    let target: TerminalStream = stream == .standardOutput
                        ? .standardOutput
                        : .standardError
                    try await terminal.write(bytes, to: target)
                },
            )
            if result.succeeded == false {
                return result.exitCode
            }
        }
        return 0
    }

    private func nonemptyEnvironmentValue(_ name: String) -> String? {
        environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }
}
