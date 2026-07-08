import Foundation
import os

/// A log severity: a display `name` plus a numeric `severity` that orders it
/// against every other level.
///
/// `LogLevel` is a struct rather than an enum so apps can define their own
/// levels alongside the standard ladder (`debug` → `info` → `notice` →
/// `warning` → `error` → `fault`). Standard severities are spaced 100 apart
/// so custom levels can slot between them:
///
/// ```swift
/// extension LogLevel {
///     static let audit = LogLevel(name: "audit", severity: 450) // warning < audit < error
/// }
/// ```
///
/// This matches OTel's severity-number + severity-text model. Two levels are
/// equal only when both name and severity match; ordering compares severity
/// alone.
public struct LogLevel: Hashable, Comparable, Codable, Sendable {
    /// Display name, e.g. `"warning"`.
    public var name: String

    /// Numeric rank used for ordering and threshold checks; higher is more
    /// severe.
    public var severity: Int

    public init(name: String, severity: Int) {
        self.name = name
        self.severity = severity
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.severity < rhs.severity
    }
}

extension LogLevel {
    public static let debug = LogLevel(name: "debug", severity: 100)
    public static let info = LogLevel(name: "info", severity: 200)
    public static let notice = LogLevel(name: "notice", severity: 300)
    public static let warning = LogLevel(name: "warning", severity: 400)
    public static let error = LogLevel(name: "error", severity: 500)
    public static let fault = LogLevel(name: "fault", severity: 600)

    /// The standard ladder, least to most severe. Custom levels are not
    /// listed here — UI that filters by level should derive choices from the
    /// levels actually present in the data, not this list alone.
    public static let standardLevels: [LogLevel] = [
        .debug,
        .info,
        .notice,
        .warning,
        .error,
        .fault,
    ]

    /// The `OSLogType` Console.app sees for this level.
    ///
    /// Mapped by severity band so custom levels inherit a sensible type.
    /// `warning` intentionally maps to `.default` (like `notice`), not
    /// `.error`, so warnings don't inflate Console's error-level queries —
    /// the same trade-off LogKit makes.
    public var osLogType: OSLogType {
        switch severity {
            case ..<LogLevel.info.severity: .debug
            case ..<LogLevel.notice.severity: .info
            case ..<LogLevel.error.severity: .default
            case ..<LogLevel.fault.severity: .error
            default: .fault
        }
    }
}
