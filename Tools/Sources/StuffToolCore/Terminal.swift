import Darwin
import Foundation

public enum TerminalStream: Equatable, Sendable {
    case standardOutput
    case standardError
}

public protocol Terminal: Sendable {
    func write(_ bytes: [UInt8], to stream: TerminalStream) async throws
    func isInteractive() async -> Bool
    func isInputInteractive() async -> Bool
    func readLine(prompt: String) async throws -> String?
}

extension Terminal {
    public func write(_ text: String, to stream: TerminalStream) async throws {
        try await write(Array(text.utf8), to: stream)
    }

    public func isInputInteractive() -> Bool {
        false
    }

    public func readLine(prompt _: String) -> String? {
        nil
    }
}

public actor StandardTerminal: Terminal {
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private let lineReader: @Sendable () -> String?

    public init() {
        standardOutput = FileHandle.standardOutput
        standardError = FileHandle.standardError
        lineReader = { Swift.readLine(strippingNewline: true) }
    }

    @_spi(Testing)
    public init(
        standardOutput: FileHandle,
        standardError: FileHandle,
        lineReader: @escaping @Sendable () -> String?,
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.lineReader = lineReader
    }

    public func write(_ bytes: [UInt8], to stream: TerminalStream) throws {
        let handle = switch stream {
            case .standardOutput:
                standardOutput
            case .standardError:
                standardError
        }
        try handle.write(contentsOf: Data(bytes))
    }

    public func isInteractive() -> Bool {
        isatty(STDOUT_FILENO) != 0
    }

    public func isInputInteractive() -> Bool {
        isatty(STDIN_FILENO) != 0
    }

    public func readLine(prompt: String) throws -> String? {
        try standardError.write(contentsOf: Data(prompt.utf8))
        return lineReader()
    }
}

/// For nested commands whose stdout is a machine-readable return value.
public struct StandardErrorOnlyTerminal: Terminal {
    private let base: any Terminal

    public init(base: any Terminal) {
        self.base = base
    }

    public func write(_ bytes: [UInt8], to stream: TerminalStream) async throws {
        guard stream == .standardError else { return }
        try await base.write(bytes, to: stream)
    }

    public func isInteractive() async -> Bool {
        await base.isInteractive()
    }

    public func isInputInteractive() async -> Bool {
        await base.isInputInteractive()
    }

    public func readLine(prompt: String) async throws -> String? {
        try await base.readLine(prompt: prompt)
    }
}
