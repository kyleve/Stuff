import Foundation

/// A UUID scoped to a domain owner. The owner is a phantom type and is never stored.
public struct TypedID<Owner>: RawRepresentable, Hashable, Comparable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID()
    }

    /// Stable UUID ordering for deterministic tie-breaking, not creation order.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

/// A single UUID value preserves the wire format of existing UUID-backed identities.
/// Encoding the owner or a keyed wrapper would change persisted records on a Swift rename.
extension TypedID: Codable {
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
