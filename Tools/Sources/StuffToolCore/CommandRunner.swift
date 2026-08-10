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
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        standardInput: [UInt8] = [],
        captureOutput: Bool = true,
        mergeStandardError: Bool = false,
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

/// Production subprocess runner backed by Swift Subprocess.
public struct CommandRunner: CommandRunning {
    public init() {}

    public func run(
        _ invocation: CommandInvocation,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        let environment = invocation.environment.reduce(
            into: [Environment.Key: String?](),
        ) { result, pair in
            guard let key = Environment.Key(rawValue: pair.key) else { return }
            result[key] = pair.value
        }
        var configuredPlatformOptions = PlatformOptions()
        configuredPlatformOptions.teardownSequence = [
            .send(signal: .interrupt, allowedDurationToNextStep: .seconds(2)),
            .gracefulShutDown(allowedDurationToNextStep: .seconds(2)),
        ]
        let platformOptions = configuredPlatformOptions
        let teardownSequence = platformOptions.teardownSequence
        let capturedOutput = CapturedCommandOutput()
        if invocation.mergeStandardError {
            return try await runCombined(
                invocation,
                environment: environment,
                platformOptions: platformOptions,
                outputHandler: outputHandler,
            )
        }
        let result = try await Subprocess.run(
            .name(invocation.executable),
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
            do {
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for try await buffer in execution.standardOutput {
                                let bytes = buffer.withUnsafeBytes { Array($0) }
                                if invocation.captureOutput {
                                    await capturedOutput.append(bytes, to: .standardOutput)
                                }
                                do {
                                    try await outputHandler?(.standardOutput, bytes)
                                } catch {
                                    await execution.teardown(using: [])
                                    throw error
                                }
                            }
                        }
                        group.addTask {
                            for try await buffer in execution.standardError {
                                let bytes = buffer.withUnsafeBytes { Array($0) }
                                if invocation.captureOutput {
                                    await capturedOutput.append(bytes, to: .standardError)
                                }
                                do {
                                    try await outputHandler?(.standardError, bytes)
                                } catch {
                                    await execution.teardown(using: [])
                                    throw error
                                }
                            }
                        }
                        try await group.waitForAll()
                    }
                } onCancel: {
                    // Stream reads do not necessarily unblock on task cancellation.
                    // Start the bounded child teardown that closes both pipes.
                    Task {
                        await execution.teardown(using: teardownSequence)
                    }
                }
            } catch {
                await execution.teardown(using: [])
                throw error
            }
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
    ) async throws -> CommandResult {
        let teardownSequence = platformOptions.teardownSequence
        let capturedOutput = CapturedCommandOutput()
        let result = try await Subprocess.run(
            .name(invocation.executable),
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
                try await withTaskCancellationHandler {
                    for try await buffer in execution.standardOutput {
                        let bytes = buffer.withUnsafeBytes { Array($0) }
                        if invocation.captureOutput {
                            await capturedOutput.append(bytes, to: .standardOutput)
                        }
                        do {
                            try await outputHandler?(.standardOutput, bytes)
                        } catch {
                            await execution.teardown(using: [])
                            throw error
                        }
                    }
                } onCancel: {
                    Task {
                        await execution.teardown(using: teardownSequence)
                    }
                }
            } catch {
                await execution.teardown(using: [])
                throw error
            }
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
