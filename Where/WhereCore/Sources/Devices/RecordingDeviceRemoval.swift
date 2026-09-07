import Foundation

/// Irreversible, append-only tombstone retiring one installation identity.
public struct RecordingDeviceRemoval: Identifiable, Codable, Sendable, Hashable {
    /// Stable identity for one immutable removal event.
    public struct ID: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(UUID.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public let id: ID
    public let deviceID: RecordingDeviceID
    public let removedAt: Date
    public let removedByDeviceID: RecordingDeviceID

    public init(
        id: ID,
        deviceID: RecordingDeviceID,
        removedAt: Date,
        removedByDeviceID: RecordingDeviceID,
    ) {
        self.id = id
        self.deviceID = deviceID
        self.removedAt = removedAt
        self.removedByDeviceID = removedByDeviceID
    }
}
