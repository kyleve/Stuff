import Foundation
import os
import PeriscopeCore

/// An in-memory `LogRecorder` that captures everything for assertions.
final class RecordingRecorder: LogRecorder, Sendable {
    private struct State {
        var scopes: [LogScope] = []
        var records: [LogRecord] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var definedScopes: [LogScope] {
        state.withLock(\.scopes)
    }

    var records: [LogRecord] {
        state.withLock(\.records)
    }

    func defineScope(_ scope: LogScope) {
        state.withLock { $0.scopes.append(scope) }
    }

    func record(_ record: LogRecord) {
        state.withLock { $0.records.append(record) }
    }
}

/// Shared fixture events used across suites.
struct AppLogs: LogEvent {
    var message: String {
        "app"
    }
}

struct PhotoLogs: LogEvent {
    var photoID: String
    var level: LogLevel {
        .notice
    }

    var message: String {
        "photo \(photoID)"
    }
}
