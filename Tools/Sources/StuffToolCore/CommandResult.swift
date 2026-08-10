import Foundation
import Subprocess

/// The complete observable result of one child-process invocation.
public struct CommandResult: Equatable, Sendable {
    public let terminationStatus: TerminationStatus
    public let standardOutput: [UInt8]
    public let standardError: [UInt8]

    public init(
        terminationStatus: TerminationStatus,
        standardOutput: [UInt8],
        standardError: [UInt8],
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool {
        terminationStatus.isSuccess
    }

    /// The shell-compatible status used by the public compatibility shims.
    public var exitCode: Int32 {
        switch terminationStatus {
            case let .exited(code):
                code
            case let .signaled(signal):
                128 + signal
        }
    }

    public var standardOutputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    public var standardErrorText: String {
        String(decoding: standardError, as: UTF8.self)
    }
}
