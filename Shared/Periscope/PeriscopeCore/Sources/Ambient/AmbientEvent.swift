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

/// The standard event ambient sources emit: environmental context —
/// backgrounding, memory pressure, connectivity, thermal state — that helps
/// diagnose what the system was doing around an error.
public struct AmbientEvent: LogEvent, Hashable {
    public static let eventName = "ambient"

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

    public var kind: AmbientKind
    /// The state as named fields (`["level": "serious"]`,
    /// `["voiceover": false]`) — a JSON object in the payload, not a
    /// formatted sentence the tooling would have to parse back apart.
    public var value: [String: AmbientValue]
    public var level: LogLevel
    /// Defaults to ``Reporting/state`` — "ambient" means a surrounding
    /// condition, and a source that reports moments is the exception.
    public var reporting: Reporting

    public var message: String {
        "\(kind): \(value.ambientDescription)"
    }

    public init(
        kind: AmbientKind,
        value: [String: AmbientValue],
        level: LogLevel = .info,
        reporting: Reporting = .state,
    ) {
        self.kind = kind
        self.value = value
        self.level = level
        self.reporting = reporting
    }
}
