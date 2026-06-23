import os

/// Severity of a captured log message, ordered from least to most severe so
/// callers can filter with comparisons (e.g. `entry.level >= .error`). The
/// cases mirror the levels `os.Logger` exposes; `osLogType` maps each back to
/// the underlying `OSLogType` the facade emits.
public enum LogLevel: Int, Sendable, Comparable, CaseIterable, Codable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The `OSLogType` the facade logs this level as. `notice` is unified
    /// logging's default level, so it maps to `.default`. Apple's unified
    /// logging has no dedicated warning level, so `warning` also maps to
    /// `.default` (the in-app viewer still shows it as a distinct level);
    /// keeping it off `.error` avoids inflating Console error-level queries.
    public var osLogType: OSLogType {
        switch self {
            case .debug: .debug
            case .info: .info
            case .notice: .default
            case .warning: .default
            case .error: .error
            case .fault: .fault
        }
    }
}
