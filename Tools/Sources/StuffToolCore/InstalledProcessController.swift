import Foundation

public struct InstalledProcessRecord: Equatable, Sendable {
    public let processID: Int32
    public let executable: String

    public init(processID: Int32, executable: String) {
        self.processID = processID
        self.executable = executable
    }
}

public struct ProcessTerminationPolicy: Equatable, Sendable {
    public let graceChecks: Int
    public let forceChecks: Int
    public let interval: Duration

    public init(graceChecks: Int, forceChecks: Int, interval: Duration) {
        self.graceChecks = graceChecks
        self.forceChecks = forceChecks
        self.interval = interval
    }
}

public struct ProcessTerminationOutcome: Equatable, Sendable {
    public let matchedProcessIDs: [Int32]
    public let forcedProcessIDs: [Int32]

    public init(matchedProcessIDs: [Int32], forcedProcessIDs: [Int32]) {
        self.matchedProcessIDs = matchedProcessIDs
        self.forcedProcessIDs = forcedProcessIDs
    }
}

public enum InstalledProcessFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)
    case exitCode(Int32)

    public var description: String {
        switch self {
            case let .message(message): message
            case let .exitCode(code): "process inspection exited with status \(code)"
        }
    }
}

/// Terminates only processes whose executable path exactly matches an installed app binary.
public struct InstalledProcessController: Sendable {
    private let runner: any CommandRunning
    private let clock: any ToolClock
    private let repository: URL
    private let policy: ProcessTerminationPolicy

    public init(
        runner: any CommandRunning,
        clock: any ToolClock,
        repository: URL,
        policy: ProcessTerminationPolicy,
    ) {
        self.runner = runner
        self.clock = clock
        self.repository = repository
        self.policy = policy
    }

    public func terminate(executable: URL) async throws -> ProcessTerminationOutcome {
        let expected = executable.standardizedFileURL.path
        let initial = try await matchingProcessIDs(expectedExecutable: expected)
        guard initial.isEmpty == false else {
            return ProcessTerminationOutcome(matchedProcessIDs: [], forcedProcessIDs: [])
        }
        for processID in initial {
            _ = try await signal("-TERM", processID: processID)
        }

        var remaining = try await waitForExit(
            expectedExecutable: expected,
            checks: policy.graceChecks,
        )
        guard remaining.isEmpty == false else {
            return ProcessTerminationOutcome(
                matchedProcessIDs: initial,
                forcedProcessIDs: [],
            )
        }

        for processID in remaining {
            _ = try await signal("-KILL", processID: processID)
        }
        let forced = remaining
        remaining = try await waitForExit(
            expectedExecutable: expected,
            checks: policy.forceChecks,
        )
        guard remaining.isEmpty else {
            throw InstalledProcessFailure.message(
                "installed Ledger process did not exit: \(remaining.map(String.init).joined(separator: ", "))",
            )
        }
        return ProcessTerminationOutcome(
            matchedProcessIDs: initial,
            forcedProcessIDs: forced,
        )
    }

    public static func parseProcessTable(_ data: Data) throws -> [InstalledProcessRecord] {
        try String(decoding: data, as: UTF8.self).split(separator: "\n").map { line in
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, let processID = Int32(fields[0]) else {
                throw InstalledProcessFailure.message(
                    "could not parse process table line: \(line)",
                )
            }
            return InstalledProcessRecord(
                processID: processID,
                executable: fields[1].trimmingCharacters(in: .whitespaces),
            )
        }
    }

    private func waitForExit(
        expectedExecutable: String,
        checks: Int,
    ) async throws -> [Int32] {
        var remaining: [Int32] = []
        for check in 0 ..< max(1, checks) {
            remaining = try await matchingProcessIDs(expectedExecutable: expectedExecutable)
            if remaining.isEmpty { return [] }
            if check < max(1, checks) - 1 {
                try await clock.sleep(for: policy.interval)
            }
        }
        return remaining
    }

    private func matchingProcessIDs(expectedExecutable: String) async throws -> [Int32] {
        let result = try await runner.run(
            CommandInvocation(
                executable: "ps",
                arguments: ["-ww", "-axo", "pid=,comm="],
                workingDirectory: repository,
            ),
        )
        guard result.succeeded else { throw InstalledProcessFailure.exitCode(result.exitCode) }
        return try Self.parseProcessTable(Data(result.standardOutput))
            .filter { $0.executable == expectedExecutable }
            .map(\.processID)
    }

    private func signal(_ signal: String, processID: Int32) async throws -> CommandResult {
        try await runner.run(
            CommandInvocation(
                executable: "kill",
                arguments: [signal, String(processID)],
                workingDirectory: repository,
            ),
        )
    }
}
