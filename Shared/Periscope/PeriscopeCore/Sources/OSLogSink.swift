import Foundation
import os

/// The built-in Console.app sink: mirrors every record to `os.Logger`.
///
/// The category is the record's *root* scope name; deeper scopes appear as a
/// `[path/below/root]` prefix on the message, so Console filters stay coarse
/// while the full hierarchy remains readable. Messages log as `.public` —
/// the same PII-free-messages contract LogKit documents.
public struct OSLogSink: LogSink {
    private struct State {
        var scopes: [ScopeID: LogScope] = [:]
        var loggers: [String: os.Logger] = [:]
    }

    public let subsystem: String
    private let state: OSAllocatedUnfairLock<State>

    public init(subsystem: String) {
        self.subsystem = subsystem
        state = OSAllocatedUnfairLock(initialState: State())
    }

    public func defineScopes(_ scopes: [LogScope]) async {
        state.withLock { state in
            for scope in scopes {
                state.scopes[scope.id] = scope
            }
        }
    }

    public func write(_ records: [LogRecord]) async {
        for record in records {
            let logger = logger(category: categoryName(for: record))
            let message = formattedMessage(for: record)
            logger.log(level: record.level.osLogType, "\(message, privacy: .public)")
        }
    }

    public func flush() async {
        // os.Logger writes synchronously; nothing buffered here.
    }

    /// The Console category: the name of the primary scope's root ancestor.
    @_spi(Testing) public func categoryName(for record: LogRecord) -> String {
        primaryPath(for: record).first?.name ?? "periscope"
    }

    /// The logged text: the primary scope path below the root (when any),
    /// then the record's message, then any tags (sorted by key).
    @_spi(Testing) public func formattedMessage(for record: LogRecord) -> String {
        var message = record.message
        let path = primaryPath(for: record).dropFirst().map(\.name)
        if !path.isEmpty {
            message = "[\(path.joined(separator: "/"))] \(message)"
        }
        if !record.tags.isEmpty {
            let tags = record.tags
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key)=\($0.value)" }
            message += " {\(tags.joined(separator: ", "))}"
        }
        return message
    }

    /// The primary scope's ancestor chain, root first. Empty when the
    /// record's primary scope was never defined here.
    private func primaryPath(for record: LogRecord) -> [LogScope] {
        guard let primary = record.scopes.first else { return [] }
        return state.withLock { state in
            var path: [LogScope] = []
            var next: ScopeID? = primary
            while let id = next, let scope = state.scopes[id] {
                path.append(scope)
                next = scope.parentID
            }
            return path.reversed()
        }
    }

    private func logger(category: String) -> os.Logger {
        state.withLock { state in
            if let logger = state.loggers[category] {
                return logger
            }
            let logger = os.Logger(subsystem: subsystem, category: category)
            state.loggers[category] = logger
            return logger
        }
    }
}
