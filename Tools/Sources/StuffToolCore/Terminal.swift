import Darwin
import Foundation

public enum TerminalStream: Equatable, Sendable {
    case standardOutput
    case standardError
}

public protocol Terminal: Sendable {
    func write(_ bytes: [UInt8], to stream: TerminalStream) async throws
    func isInteractive() async -> Bool
}

extension Terminal {
    public func write(_ text: String, to stream: TerminalStream) async throws {
        try await write(Array(text.utf8), to: stream)
    }
}

public actor StandardTerminal: Terminal {
    public init() {}

    public func write(_ bytes: [UInt8], to stream: TerminalStream) throws {
        let handle = switch stream {
            case .standardOutput:
                FileHandle.standardOutput
            case .standardError:
                FileHandle.standardError
        }
        try handle.write(contentsOf: Data(bytes))
    }

    public func isInteractive() -> Bool {
        isatty(STDOUT_FILENO) != 0
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
}
