import Dispatch
import Foundation

/// Thin wrappers over `Process` for the few external commands the extractor
/// needs (xcrun, git, tuist, xcodebuild).
enum Shell {
    /// Runs a command and returns its stdout. Throws on a non-zero exit. Use
    /// only for short-lived commands whose output comfortably fits a pipe.
    @discardableResult
    static func capture(
        _ executable: String,
        _ arguments: [String],
        cwd: String? = nil,
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Drain stdout and stderr concurrently: reading one pipe to EOF before
        // touching the other deadlocks if the child fills the second pipe's
        // ~64KB buffer while we're still blocked on the first. (A
        // DispatchWorkItem block isn't `@Sendable`, so it can hold the file
        // handle / accumulator without tripping strict-concurrency checks.)
        let errHandle = stderr.fileHandleForReading
        var errData = Data()
        let drainStderr = DispatchWorkItem { errData = errHandle.readDataToEndOfFile() }
        DispatchQueue.global(qos: .userInitiated).async(execute: drainStderr)
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        drainStderr.wait()
        process.waitUntilExit()
        let output = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ExtractError.processFailed(
                command: ([executable] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                output: output + String(decoding: errData, as: UTF8.self),
            )
        }
        return output
    }

    /// Runs a command inheriting the parent's stdout/stderr so long builds
    /// stream their progress live. Throws on a non-zero exit.
    static func runStreaming(
        _ executable: String,
        _ arguments: [String],
        cwd: String? = nil,
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ExtractError.processFailed(
                command: ([executable] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                output: "(see streamed output above)",
            )
        }
    }
}
