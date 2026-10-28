import CryptoKit
import Foundation

/// The identity of a scope in the log hierarchy.
///
/// Scope IDs are **deterministic**: an ID is derived from the parent's ID and
/// the scope's name, so deriving the same path twice — in two places, or in
/// two different launches — yields the *same* scope. That's what lets a model
/// layer and the UI arrive at a shared scope independently, and what keeps
/// weeks of persisted logs pointing at one scope row per path.
public struct ScopeID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public var description: String {
        rawValue.uuidString
    }

    /// Fixed namespace mixed into every derivation so Periscope scope IDs
    /// can't collide with other UUID sources.
    private static let namespace = Data("com.stuff.periscope.scope".utf8)

    /// Derive the ID for a scope `name` under `parent` (`nil` for roots):
    /// SHA-256 over namespace + parent + name, truncated to a UUID.
    static func derive(parent: ScopeID?, name: String) -> ScopeID {
        var hasher = SHA256()
        hasher.update(data: namespace)
        if let parent {
            withUnsafeBytes(of: parent.rawValue.uuid) { hasher.update(bufferPointer: $0) }
        }
        hasher.update(data: Data(name.utf8))
        let digest = Array(hasher.finalize().prefix(16))
        let uuid = UUID(uuid: (
            digest[0],
            digest[1],
            digest[2],
            digest[3],
            digest[4],
            digest[5],
            digest[6],
            digest[7],
            digest[8],
            digest[9],
            digest[10],
            digest[11],
            digest[12],
            digest[13],
            digest[14],
            digest[15],
        ))
        return ScopeID(rawValue: uuid)
    }
}

extension ScopeID: Codable {
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
