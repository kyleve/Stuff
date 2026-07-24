import Foundation

/// Identifies a connector within one app (e.g. `app`, `ui`, `where`). Typed so a
/// new id can't silently typo into an untracked one; lowercase-kebab by
/// convention.
public struct PortholeConnectorID: RawRepresentable, Hashable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}

/// Identifies an action within its connector.
public struct PortholeActionID: RawRepresentable, Hashable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}

/// Identifies a data source within its connector.
public struct PortholeDataSourceID: RawRepresentable, Hashable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}

/// A fully-qualified action address: which connector, which action.
public struct PortholeActionRef: Hashable, Sendable, Codable, CustomStringConvertible {
    public var connector: PortholeConnectorID
    public var action: PortholeActionID

    public init(connector: PortholeConnectorID, action: PortholeActionID) {
        self.connector = connector
        self.action = action
    }

    public var description: String {
        "\(connector)/\(action)"
    }
}

/// A fully-qualified data-source address: which connector, which source.
public struct PortholeDataSourceRef: Hashable, Sendable, Codable, CustomStringConvertible {
    public var connector: PortholeConnectorID
    public var source: PortholeDataSourceID

    public init(connector: PortholeConnectorID, source: PortholeDataSourceID) {
        self.connector = connector
        self.source = source
    }

    public var description: String {
        "\(connector)/\(source)"
    }
}
