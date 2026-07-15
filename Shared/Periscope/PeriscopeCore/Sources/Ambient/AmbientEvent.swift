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

    public var kind: AmbientKind
    public var value: String
    public var level: LogLevel

    public var message: String {
        "\(kind): \(value)"
    }

    public init(kind: AmbientKind, value: String, level: LogLevel = .info) {
        self.kind = kind
        self.value = value
        self.level = level
    }
}
