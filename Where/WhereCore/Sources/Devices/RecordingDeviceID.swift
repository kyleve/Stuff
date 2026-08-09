import Foundation

/// Stable identity of one installation that can record automatic locations.
///
/// The value encodes as a single `store://devices/<uuid>` URL so the same
/// identity is readable in backups, SwiftData, and structured logs without
/// exposing a raw, stringly-typed key.
public struct RecordingDeviceID: Hashable, Sendable, Identifiable, WhereStoreURLCodable {
    public let rawValue: UUID

    public var id: RecordingDeviceID {
        self
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var storeURL: URL {
        StoreURL.url(
            collection: "devices",
            type: rawValue.uuidString.lowercased(),
            items: [:],
        )
    }

    public init?(storeURL: URL) {
        guard let parts = StoreURL.parts(of: storeURL),
              parts.collection == "devices",
              parts.items.isEmpty,
              let rawValue = UUID(uuidString: parts.type)
        else { return nil }
        self.rawValue = rawValue
    }
}
