import Foundation

/// A role-specific identifier whose wire representation is one string.
public struct PortholeIdentifier<Role>: Hashable, Sendable, Codable, RawRepresentable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    /// Single-value coding preserves an identifier as a string at tool boundaries.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum PortholeSymbolRole: Sendable {}
public enum PortholeModuleRole: Sendable {}
public enum PortholeScopeRole: Sendable {}
public enum PortholeContextRole: Sendable {}
public typealias PortholeSymbolID = PortholeIdentifier<PortholeSymbolRole>
public typealias PortholeModuleID = PortholeIdentifier<PortholeModuleRole>
public typealias PortholeScopeID = PortholeIdentifier<PortholeScopeRole>
public typealias PortholeContextID = PortholeIdentifier<PortholeContextRole>
