import Foundation
import os

/// A logging facade that fans a single call out to both Apple unified logging
/// (`os.Logger`, for Console.app) and — in DEBUG builds — an in-memory
/// ``LogStore`` the in-app viewer reads.
///
/// Messages are passed as already-rendered `String`s rather than `os`
/// interpolations. That is a deliberate trade-off: it lets us capture the text
/// for the buffer, but means per-argument `os` privacy (`privacy: .public` /
/// `.private`) is not available — the whole message is logged as `.public`.
/// Use this for operational diagnostics, not for anything carrying PII.
public struct LogChannel: Sendable {
    private let logger: Logger
    private let subsystem: String
    private let category: String
    private let store: LogStore?

    public init(subsystem: String, category: String, store: LogStore? = nil) {
        logger = Logger(subsystem: subsystem, category: category)
        self.subsystem = subsystem
        self.category = category
        self.store = store
    }

    public func debug(_ message: @autoclosure () -> String) {
        emit(.debug, message())
    }

    public func info(_ message: @autoclosure () -> String) {
        emit(.info, message())
    }

    public func notice(_ message: @autoclosure () -> String) {
        emit(.notice, message())
    }

    public func warning(_ message: @autoclosure () -> String) {
        emit(.warning, message())
    }

    public func error(_ message: @autoclosure () -> String) {
        emit(.error, message())
    }

    public func fault(_ message: @autoclosure () -> String) {
        emit(.fault, message())
    }

    private func emit(_ level: LogLevel, _ message: String) {
        logger.log(level: level.osLogType, "\(message, privacy: .public)")
        #if DEBUG
            store?.record(LogEntry(
                level: level,
                subsystem: subsystem,
                category: category,
                message: message,
            ))
        #endif
    }
}
