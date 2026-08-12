import Darwin
import Foundation
import Subprocess

/// Runs executables without passing arguments through a shell.
public protocol CommandRunning: Sendable {
    func run(
        _ invocation: CommandInvocation,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult
}

extension CommandRunning {
    public func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        try await run(invocation, outputHandler: nil)
    }
}

public enum CommandOutputStream: Equatable, Sendable {
    case standardOutput
    case standardError
}

public typealias CommandOutputHandler = @Sendable (
    CommandOutputStream,
    [UInt8],
) async throws -> Void

/// Selects whether command output is retained and whether stderr remains separate.
public enum CommandOutputMode: Equatable, Sendable {
    case captured
    case streamed
    case merged

    fileprivate var capturesOutput: Bool {
        self == .captured
    }
}

/// A value description of one subprocess, suitable for assertions in tests.
public struct CommandInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let standardInput: [UInt8]
    public let output: CommandOutputMode

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        standardInput: [UInt8],
        output: CommandOutputMode,
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.standardInput = standardInput
        self.output = output
    }
}

/// A subprocess that the operating system could not launch.
public struct CommandLaunchFailure: Error, CustomStringConvertible, Sendable {
    public let exitStatus: Int32
    public let description: String

    public init(exitStatus: Int32, description: String) {
        self.exitStatus = exitStatus
        self.description = description
    }
}

/// Production subprocess runner backed by Swift Subprocess.
///
/// Children stay in the tool's foreground process group so terminal-generated
/// job-control signals reach the whole command tree naturally.
public struct CommandRunner: CommandRunning {
    public init() {}

    public func run(
        _ invocation: CommandInvocation,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        do {
            return try await runCommand(invocation, outputHandler: outputHandler)
        } catch let error as SubprocessError {
            guard error.code == .executableNotFound || error.code == .spawnFailed else {
                throw error
            }
            throw CommandLaunchFailure(
                exitStatus: executableCandidateExists(for: invocation) ? 126 : 127,
                description: error.description,
            )
        }
    }

    private func runCommand(
        _ invocation: CommandInvocation,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        try Task.checkCancellation()
        let environment = invocation.environment.reduce(
            into: [Environment.Key: String?](),
        ) { result, pair in
            guard let key = Environment.Key(rawValue: pair.key) else { return }
            result[key] = pair.value
        }
        var platformOptions = PlatformOptions()
        platformOptions.teardownSequence = commandTeardownSequence

        if invocation.output == .merged {
            return try await runMerged(
                invocation,
                environment: environment,
                platformOptions: platformOptions,
                outputHandler: outputHandler,
            )
        }

        let capturedOutput = CapturedCommandOutput()
        let result = try await Subprocess.run(
            subprocessExecutable(invocation.executable),
            arguments: Arguments(invocation.arguments),
            environment: invocation.environment.isEmpty
                ? .inherit
                : .inherit.updating(environment),
            workingDirectory: invocation.workingDirectory.map { .init($0.path) },
            platformOptions: platformOptions,
            input: .array(invocation.standardInput),
            output: .sequence,
            error: .sequence,
        ) { execution in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await buffer in execution.standardOutput {
                        let bytes = buffer.withUnsafeBytes { Array($0) }
                        if invocation.output.capturesOutput {
                            await capturedOutput.append(bytes, to: .standardOutput)
                        }
                        try await outputHandler?(.standardOutput, bytes)
                    }
                }
                group.addTask {
                    for try await buffer in execution.standardError {
                        let bytes = buffer.withUnsafeBytes { Array($0) }
                        if invocation.output.capturesOutput {
                            await capturedOutput.append(bytes, to: .standardError)
                        }
                        try await outputHandler?(.standardError, bytes)
                    }
                }
                do {
                    while try await group.next() != nil {}
                } catch {
                    await execution.teardown(using: commandTeardownSequence)
                    group.cancelAll()
                    throw error
                }
            }
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        let output = await capturedOutput.value
        return CommandResult(
            terminationStatus: result.terminationStatus,
            standardOutput: output.standardOutput,
            standardError: output.standardError,
        )
    }

    private func runMerged(
        _ invocation: CommandInvocation,
        environment: [Environment.Key: String?],
        platformOptions: PlatformOptions,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        let result = try await Subprocess.run(
            subprocessExecutable(invocation.executable),
            arguments: Arguments(invocation.arguments),
            environment: invocation.environment.isEmpty
                ? .inherit
                : .inherit.updating(environment),
            workingDirectory: invocation.workingDirectory.map { .init($0.path) },
            platformOptions: platformOptions,
            input: .array(invocation.standardInput),
            output: .sequence,
            error: .combinedWithOutput,
        ) { execution in
            do {
                for try await buffer in execution.standardOutput {
                    let bytes = buffer.withUnsafeBytes { Array($0) }
                    try await outputHandler?(.standardOutput, bytes)
                }
                try Task.checkCancellation()
            } catch {
                await execution.teardown(using: commandTeardownSequence)
                throw error
            }
        }
        try Task.checkCancellation()
        return CommandResult(
            terminationStatus: result.terminationStatus,
            standardOutput: [],
            standardError: [],
        )
    }
}

private func executableCandidateExists(for invocation: CommandInvocation) -> Bool {
    if invocation.executable.contains("/") {
        let base = invocation.workingDirectory ?? URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory,
        )
        return FileManager.default.fileExists(
            atPath: URL(filePath: invocation.executable, relativeTo: base)
                .standardizedFileURL
                .path,
        )
    }
    let path = invocation.environment["PATH"]
        ?? ProcessInfo.processInfo.environment["PATH"]
        ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
    return path.split(separator: ":")
        .lazy
        .map(String.init)
        .filter { $0.hasPrefix("/") }
        .contains { directory in
            FileManager.default.fileExists(
                atPath: URL(filePath: directory, directoryHint: .isDirectory)
                    .appending(path: invocation.executable)
                    .path,
            )
        }
}

private func subprocessExecutable(_ executable: String) -> Executable {
    executable.contains("/") ? .path(.init(executable)) : .name(executable)
}

private let commandTeardownSequence: [TeardownStep] = [
    .send(signal: .interrupt, allowedDurationToNextStep: .seconds(2)),
    .gracefulShutDown(allowedDurationToNextStep: .seconds(2)),
]

private actor CapturedCommandOutput {
    private var standardOutput: [UInt8] = []
    private var standardError: [UInt8] = []

    func append(_ bytes: [UInt8], to stream: CommandOutputStream) {
        switch stream {
            case .standardOutput:
                standardOutput.append(contentsOf: bytes)
            case .standardError:
                standardError.append(contentsOf: bytes)
        }
    }

    var value: (standardOutput: [UInt8], standardError: [UInt8]) {
        (standardOutput, standardError)
    }
}
