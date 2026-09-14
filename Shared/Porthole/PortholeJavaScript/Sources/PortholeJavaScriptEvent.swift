import Foundation
import PortholeCore

public enum PortholeJavaScriptError: Error, Sendable, Equatable {
    case busy
    case invalidConfiguration
    case sourceTooLarge
    case valueTooLarge
    case engineUnavailable
    case executionFailed(String)
    case timedOut
    case cancelled
}

/// Events contain tool-visible values. Credentials never enter the console.
public enum PortholeJavaScriptEvent: Sendable, Equatable {
    public struct CallID: Sendable, Equatable, Hashable {
        public let runID: UUID
        public let sequence: UInt64
    }

    case started(runID: UUID)
    case nativeCall(callID: CallID, name: String, arguments: PortholeValue)
    case nativeResult(callID: CallID, value: PortholeValue)
    case nativeFailure(callID: CallID, message: String)
    case finished(runID: UUID, value: PortholeValue)
    case failed(runID: UUID, error: PortholeJavaScriptError)
}
