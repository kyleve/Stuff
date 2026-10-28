import Foundation

/// The category of an ambient event — typed so a kind can't silently typo
/// into a new, untracked identifier. Apps add their own:
///
/// ```swift
/// extension AmbientKind {
///     static let pushToken = AmbientKind("push-token")
/// }
/// ```
public struct AmbientKind: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

extension AmbientKind {
    public static let appLifecycle = AmbientKind("app-lifecycle")
    public static let memory = AmbientKind("memory")
    public static let network = AmbientKind("network")
    public static let thermalState = AmbientKind("thermal-state")
    public static let powerMode = AmbientKind("power-mode")
    public static let accessibility = AmbientKind("accessibility")
}

/// One field of an ambient value: a bare JSON scalar.
///
/// The `Codable` conformance is hand-written for the load-bearing
/// single-value wire shape (see the root `AGENTS.md` on synthesized
/// `Codable`): a field encodes as the scalar itself — `true`, `3`,
/// `"serious"` — so an ambient value reads as a plain JSON object wherever
/// the payload surfaces, instead of the case-keyed wrapper a synthesized
/// enum would emit.
public enum AmbientValue: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    /// The canonical display string for this field.
    public var stringValue: String {
        switch self {
            case let .string(value): value
            case let .int(value): String(value)
            case let .double(value): String(value)
            case let .bool(value): String(value)
        }
    }
}

extension AmbientValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before the numeric types: JSON `true` is decodable as a
        // number by some coders, and `1` is never decodable as a Bool.
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else {
            self = try .string(container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case let .string(value): try container.encode(value)
            case let .int(value): try container.encode(value)
            case let .double(value): try container.encode(value)
            case let .bool(value): try container.encode(value)
        }
    }
}

extension AmbientValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral
{
    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(floatLiteral value: Double) {
        self = .double(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension [String: AmbientValue] {
    /// The sorted `key=value` rendering shared by log messages and tooling —
    /// deterministic, so equal values always read (and diff) identically.
    public var ambientDescription: String {
        sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: ", ")
    }
}

/// Snapshot data for both classified built-ins and restricted custom events.
/// This projection is local-only and does not approve fields for remote export.
public protocol AmbientLogEvent: Sendable {
    var kind: AmbientKind { get }
    var value: [String: AmbientValue] { get }
    var reporting: AmbientLog.Event.Reporting { get }
}

/// The built-in scope for environmental state and occurrence events.
@LogScope("ambient")
public enum AmbientLog {
    /// A closed lifecycle phase, explicitly approved for baseline export.
    @LogEvent("app-lifecycle")
    public struct AppLifecycle: AmbientLogEvent {
        public enum Phase: String, Codable, Sendable, CaseIterable {
            case background, foreground, active, inactive
        }

        @LogField(exposure: .shareable, kind: .category)
        public var phase: AmbientLog.AppLifecycle.Phase

        public var kind: AmbientKind {
            .appLifecycle
        }

        public var value: [String: AmbientValue] {
            ["phase": .string(phase.rawValue)]
        }

        public var reporting: AmbientLog.Event.Reporting {
            .state
        }

        public var message: String {
            "\(kind): \(value.ambientDescription)"
        }
    }

    /// A closed thermal condition, without any device identifier.
    @LogEvent("thermal-state")
    public struct ThermalState: AmbientLogEvent {
        public enum Condition: String, Codable, Sendable, CaseIterable {
            case nominal, fair, serious, critical, unknown
        }

        @LogField(exposure: .shareable, kind: .category)
        public var condition: AmbientLog.ThermalState.Condition

        public var kind: AmbientKind {
            .thermalState
        }

        public var value: [String: AmbientValue] {
            ["level": .string(condition.rawValue)]
        }

        public var reporting: AmbientLog.Event.Reporting {
            .state
        }

        public var message: String {
            "\(kind): \(value.ambientDescription)"
        }

        public var level: LogLevel {
            switch condition {
                case .nominal, .fair, .unknown: .info
                case .serious, .critical: .warning
            }
        }
    }

    /// The current power-saving flag, explicitly approved for baseline export.
    @LogEvent("power-mode")
    public struct PowerMode: AmbientLogEvent {
        @LogField("low_power", exposure: .shareable, kind: .boolean)
        public var enabled: Bool

        public var kind: AmbientKind {
            .powerMode
        }

        public var value: [String: AmbientValue] {
            ["low-power": .bool(enabled)]
        }

        public var reporting: AmbientLog.Event.Reporting {
            .state
        }

        public var message: String {
            "\(kind): \(value.ambientDescription)"
        }
    }

    /// A momentary memory warning. Event identity carries the signal.
    @LogEvent("memory-warning", level: .warning, message: "memory: pressure=warning")
    public struct MemoryWarning: AmbientLogEvent {
        public var kind: AmbientKind {
            .memory
        }

        public var value: [String: AmbientValue] {
            ["pressure": .string("warning")]
        }

        public var reporting: AmbientLog.Event.Reporting {
            .occurrence
        }
    }

    /// Connectivity is approved; detailed interface information remains local.
    @LogEvent("network")
    public struct Network: Hashable, AmbientLogEvent {
        public enum Status: String, Codable, Sendable, CaseIterable {
            case satisfied, unsatisfied
            case requiresConnection = "requires-connection"
            case unknown
        }

        public enum Interface: String, Codable, Sendable {
            case wifi, cellular, wired, loopback, other, unknown
        }

        @LogField(exposure: .shareable, kind: .category)
        public var status: AmbientLog.Network.Status

        @LogField(exposure: .restricted, kind: .technicalState)
        public var interfaces: [AmbientLog.Network.Interface]

        public var kind: AmbientKind {
            .network
        }

        public var value: [String: AmbientValue] {
            var result: [String: AmbientValue] = ["status": .string(status.rawValue)]
            if status == .satisfied {
                result["interfaces"] = .string(interfaces.map(\.rawValue).joined(separator: ", "))
            }
            return result
        }

        public var reporting: AmbientLog.Event.Reporting {
            .state
        }

        public var message: String {
            "\(kind): \(value.ambientDescription)"
        }
    }

    /// Restricted custom ambient data, including accessibility settings.
    /// A built-in kind name does not grant baseline export approval.
    @LogEvent("event")
    public struct Event: Hashable, AmbientLogEvent {
        /// Whether an event announces a lasting condition or a passing moment.
        ///
        /// Only `state` folds into the ``AmbientSnapshot`` every later record is
        /// stamped with. A memory warning describes an instant, not a condition
        /// the app stays in, so it must not stick to everything after it.
        ///
        /// The case names are the persisted wire values — renaming one rewrites
        /// the format for stored rows.
        public enum Reporting: String, Hashable, Sendable, Codable {
            /// A lasting condition: the newest value replaces the previous one
            /// and describes the app until it changes again.
            case state
            /// A momentary occurrence, meaningful only at its own timestamp.
            case occurrence
        }

        @LogField(
            exposure: .restricted,
            kind: .technicalState,
        )
        public var kind: AmbientKind

        /// The state as named fields (`["level": "serious"]`,
        /// `["voiceover": false]`) — a JSON object in the payload, not a
        /// formatted sentence the tooling would have to parse back apart.
        @LogField(
            exposure: .restricted,
            kind: .domainValue,
        )
        public var value: [String: AmbientValue]

        @LogField(
            exposure: .restricted,
            kind: .technicalState,
        )
        public var level: LogLevel

        @LogField(
            exposure: .restricted,
            kind: .technicalState,
        )
        public var reporting: AmbientLog.Event.Reporting

        /// Local display, OSLog, and stored-message search use this rendering.
        /// Stored text also survives when a historical payload cannot decode;
        /// JSON alone does not retain the formatter that produced this message.
        public var message: String {
            "\(kind): \(value.ambientDescription)"
        }
    }
}
