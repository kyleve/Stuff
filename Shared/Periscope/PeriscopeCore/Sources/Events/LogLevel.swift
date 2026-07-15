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

    /// The `OSLogType` Console.app sees for records at this level —
    /// severity-band default from ``defaultOSLogType(forSeverity:)``, or
    /// whatever a custom level passed at init. Not part of a level's
    /// identity, and not persisted: it only routes live OSLog mirroring,
    /// so decoded levels re-derive the band default.
    public var osLogType: OSLogType

    public init(name: String, severity: Int) {
        self.init(
            name: name,
            severity: severity,
            osLogType: Self.defaultOSLogType(forSeverity: severity),
        )
    }

    /// A level with an explicit OSLog mapping — for custom levels whose
    /// Console visibility shouldn't follow their severity band (say, an
    /// `audit` level between warning and error that must surface as
    /// `.error`).
    public init(name: String, severity: Int, osLogType: OSLogType) {
        self.name = name
        self.severity = severity
        self.osLogType = osLogType
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.severity < rhs.severity
    }

    // Identity is name + severity alone, as documented above — the OSLog
    // mapping is routing metadata, not part of what a level *is*.

    public static func == (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.name == rhs.name && lhs.severity == rhs.severity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(severity)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case severity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            severity: container.decode(Int.self, forKey: .severity),
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(severity, forKey: .severity)
    }
}

extension LogLevel {
    // Explicit OSLog mappings, not the band default: these initializers
    // must not call defaultOSLogType(forSeverity:), which reads the very
    // statics being initialized — recursive static init traps at runtime.
    public static let debug = LogLevel(name: "debug", severity: 100, osLogType: .debug)
    public static let info = LogLevel(name: "info", severity: 200, osLogType: .info)
    public static let notice = LogLevel(name: "notice", severity: 300, osLogType: .default)
    public static let warning = LogLevel(name: "warning", severity: 400, osLogType: .default)
    public static let error = LogLevel(name: "error", severity: 500, osLogType: .error)
    public static let fault = LogLevel(name: "fault", severity: 600, osLogType: .fault)

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

    /// The severity-band default OSLog mapping.
    ///
    /// `warning` intentionally maps to `.default` (like `notice`), not
    /// `.error`, so warnings don't inflate Console's error-level queries —
    /// the same trade-off LogKit makes.
    public static func defaultOSLogType(forSeverity severity: Int) -> OSLogType {
        switch severity {
            case ..<LogLevel.info.severity: .debug
            case ..<LogLevel.notice.severity: .info
            case ..<LogLevel.error.severity: .default
            case ..<LogLevel.fault.severity: .error
            default: .fault
        }
    }
}
