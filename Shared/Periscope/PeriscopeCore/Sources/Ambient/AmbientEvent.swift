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

/// The standard event ambient sources emit: environmental context —
/// backgrounding, memory pressure, connectivity, thermal state — that helps
/// diagnose what the system was doing around an error.
public struct AmbientEvent: LogEvent, Hashable {
    public static let eventName = "ambient"
    /// v2 added ``reporting``; v1 rows decode as ``Reporting/state``.
    public static let eventVersion = 2

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
    public var value: String
    public var level: LogLevel
    /// Defaults to ``Reporting/state`` — "ambient" means a surrounding
    /// condition, and a source that reports moments is the exception.
    public var reporting: Reporting

    public var message: String {
        "\(kind): \(value)"
    }

    public init(
        kind: AmbientKind,
        value: String,
        level: LogLevel = .info,
        reporting: Reporting = .state,
    ) {
        self.kind = kind
        self.value = value
        self.level = level
        self.reporting = reporting
    }
}

/// Hand-written `init(from:)` for one load-bearing reason: rows written as
/// v1 have no `reporting` key, and synthesized decoding throws on a missing
/// key rather than defaulting. Every v1 ambient event was a state change —
/// the momentary distinction arrived with the snapshot — so absence decodes
/// as `.state`. `encode(to:)` stays synthesized.
extension AmbientEvent {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case level
        case reporting
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(AmbientKind.self, forKey: .kind)
        value = try container.decode(String.self, forKey: .value)
        level = try container.decode(LogLevel.self, forKey: .level)
        reporting = try container.decodeIfPresent(Reporting.self, forKey: .reporting) ?? .state
    }
}
