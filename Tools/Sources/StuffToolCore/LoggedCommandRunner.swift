import Foundation

/// Streams a subprocess into a raw log without retaining a second copy in memory.
public struct LoggedCommandRunner: Sendable {
    private let runner: any CommandRunning
    private let fileSystem: any FileSystem

    public init(runner: any CommandRunning, fileSystem: any FileSystem) {
        self.runner = runner
        self.fileSystem = fileSystem
    }

    public func run(
        _ invocation: CommandInvocation,
        logURL: URL,
    ) async throws -> CommandResult {
        let writer = try CommandLogWriter(url: logURL, fileSystem: fileSystem)
        do {
            let result = try await runner.run(
                invocation,
                outputHandler: { _, bytes in
                    try await writer.append(bytes)
                },
            )
            try await writer.finish()
            return result
        } catch {
            try? await writer.finish()
            throw error
        }
    }
}

private actor CommandLogWriter {
    private let handle: FileHandle
    private var isOpen = true

    init(url: URL, fileSystem: any FileSystem) throws {
        try fileSystem.write(Data(), to: url, atomically: false)
        handle = try FileHandle(forWritingTo: url)
    }

    func append(_ bytes: [UInt8]) throws {
        guard isOpen else { return }
        try handle.write(contentsOf: Data(bytes))
    }

    func finish() throws {
        guard isOpen else { return }
        try handle.close()
        isOpen = false
    }
}
