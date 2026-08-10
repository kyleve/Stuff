import Foundation

public enum TerminalStream: Equatable, Sendable {
    case standardOutput
    case standardError
}

public protocol Terminal: Sendable {
    func write(_ bytes: [UInt8], to stream: TerminalStream) async throws
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
}
