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

/// An in-memory `LogSink` that captures deliveries in order for assertions.
final class CapturingSink: LogSink, Sendable {
    enum Delivery {
        case scopes([LogScope])
        case records([LogRecord])
    }

    private struct State {
        var deliveries: [Delivery] = []
        var flushCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var deliveries: [Delivery] {
        state.withLock(\.deliveries)
    }

    var flushCount: Int {
        state.withLock(\.flushCount)
    }

    var definedScopes: [LogScope] {
        deliveries.flatMap { delivery -> [LogScope] in
            guard case let .scopes(scopes) = delivery else { return [] }
            return scopes
        }
    }

    var records: [LogRecord] {
        deliveries.flatMap { delivery -> [LogRecord] in
            guard case let .records(records) = delivery else { return [] }
            return records
        }
    }

    func defineScopes(_ scopes: [LogScope]) async {
        state.withLock { $0.deliveries.append(.scopes(scopes)) }
    }

    func write(_ records: [LogRecord]) async {
        state.withLock { $0.deliveries.append(.records(records)) }
    }

    func flush() async {
        state.withLock { $0.flushCount += 1 }
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
