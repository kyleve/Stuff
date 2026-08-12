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

/// A value description of one subprocess, suitable for assertions in tests.
public struct CommandInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let standardInput: [UInt8]
    public let captureOutput: Bool
    public let mergeStandardError: Bool

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        standardInput: [UInt8],
        captureOutput: Bool,
        mergeStandardError: Bool,
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.standardInput = standardInput
        self.captureOutput = captureOutput
        self.mergeStandardError = mergeStandardError
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
        let relay = CommandSignalRelay.current ?? CommandSignalRelay()
        let environment = invocation.environment.reduce(
            into: [Environment.Key: String?](),
        ) { result, pair in
            guard let key = Environment.Key(rawValue: pair.key) else { return }
            result[key] = pair.value
        }
        var configuredPlatformOptions = PlatformOptions()
        configuredPlatformOptions.createSession = true
        configuredPlatformOptions.teardownSequence = commandTeardownSequence()
        let platformOptions = configuredPlatformOptions
        let capturedOutput = CapturedCommandOutput()
        if invocation.mergeStandardError {
            return try await runCombined(
                invocation,
                environment: environment,
                platformOptions: platformOptions,
                outputHandler: outputHandler,
                relay: relay,
            )
        }
        let registration = relay.reserve()
        defer { relay.complete(registration) }
        let result = try await withTaskCancellationHandler {
            try await Subprocess.run(
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
                relay.attach(
                    registration,
                    processGroupID: execution.processIdentifier.value,
                )
                defer { relay.finish(registration) }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await buffer in execution.standardOutput {
                            let bytes = buffer.withUnsafeBytes { Array($0) }
                            if invocation.captureOutput {
                                await capturedOutput.append(bytes, to: .standardOutput)
                            }
                            try await outputHandler?(.standardOutput, bytes)
                        }
                    }
                    group.addTask {
                        for try await buffer in execution.standardError {
                            let bytes = buffer.withUnsafeBytes { Array($0) }
                            if invocation.captureOutput {
                                await capturedOutput.append(bytes, to: .standardError)
                            }
                            try await outputHandler?(.standardError, bytes)
                        }
                    }
                    do {
                        while try await group.next() != nil {}
                    } catch {
                        await execution.teardown(
                            using: commandTeardownSequence(after: error, relay: relay),
                        )
                        try forceKillProcessGroup(execution.processIdentifier.value)
                        group.cancelAll()
                        throw error
                    }
                }
                if Task.isCancelled {
                    await execution.teardown(
                        using: commandTeardownSequence(firstSignal: relay.firstSignal),
                    )
                    try forceKillProcessGroup(execution.processIdentifier.value)
                    throw CancellationError()
                }
            }
        } onCancel: {
            relay.beginCancellation(registration)
        }
        try Task.checkCancellation()
        let output = await capturedOutput.value
        return CommandResult(
            terminationStatus: result.terminationStatus,
            standardOutput: output.standardOutput,
            standardError: output.standardError,
        )
    }

    private func runCombined(
        _ invocation: CommandInvocation,
        environment: [Environment.Key: String?],
        platformOptions: PlatformOptions,
        outputHandler: CommandOutputHandler?,
        relay: CommandSignalRelay,
    ) async throws -> CommandResult {
        let capturedOutput = CapturedCommandOutput()
        let registration = relay.reserve()
        defer { relay.complete(registration) }
        let result = try await withTaskCancellationHandler {
            try await Subprocess.run(
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
                relay.attach(
                    registration,
                    processGroupID: execution.processIdentifier.value,
                )
                defer { relay.finish(registration) }
                do {
                    for try await buffer in execution.standardOutput {
                        let bytes = buffer.withUnsafeBytes { Array($0) }
                        if invocation.captureOutput {
                            await capturedOutput.append(bytes, to: .standardOutput)
                        }
                        try await outputHandler?(.standardOutput, bytes)
                    }
                    try Task.checkCancellation()
                } catch {
                    await execution.teardown(
                        using: commandTeardownSequence(after: error, relay: relay),
                    )
                    try forceKillProcessGroup(execution.processIdentifier.value)
                    throw error
                }
            }
        } onCancel: {
            relay.beginCancellation(registration)
        }
        try Task.checkCancellation()
        let output = await capturedOutput.value
        return CommandResult(
            terminationStatus: result.terminationStatus,
            standardOutput: output.standardOutput,
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

private func commandTeardownSequence(
    firstSignal: CommandSignal? = nil,
) -> [TeardownStep] {
    [
        .send(
            // The relay already sent a latched terminal signal. Signal zero
            // provides its grace period without racing it with a duplicate.
            signal: Signal(rawValue: firstSignal == nil ? SIGINT : 0),
            toProcessGroup: true,
            allowedDurationToNextStep: .seconds(2),
        ),
        .gracefulShutDown(
            toProcessGroup: true,
            allowedDurationToNextStep: .seconds(2),
        ),
    ]
}

private func commandTeardownSequence(
    after error: any Error,
    relay: CommandSignalRelay,
) -> [TeardownStep] {
    if isBrokenPipe(error), relay.firstSignal == nil {
        relay.receiveBrokenPipeError()
    }
    return commandTeardownSequence(firstSignal: relay.firstSignal)
}

private func isBrokenPipe(_ error: any Error) -> Bool {
    var current: NSError? = error as NSError
    while let candidate = current {
        if candidate.domain == NSPOSIXErrorDomain, candidate.code == EPIPE {
            return true
        }
        current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return false
}

private func forceKillProcessGroup(_ processGroupID: Int32) throws {
    guard Darwin.kill(-processGroupID, SIGKILL) != 0 else { return }
    // Darwin can report EPERM once a session contains only unsignalable
    // zombies. The preceding teardown already waited for its leader.
    guard errno != ESRCH, errno != EPERM else { return }
    guard let errorCode = POSIXErrorCode(rawValue: errno) else {
        throw CocoaError(.fileWriteUnknown)
    }
    throw POSIXError(errorCode)
}

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
