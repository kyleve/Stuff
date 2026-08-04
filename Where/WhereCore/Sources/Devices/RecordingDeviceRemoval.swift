import Foundation

/// Irreversible, append-only tombstone retiring one installation identity.
public struct RecordingDeviceRemoval: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deviceID: RecordingDeviceID
    public let removedAt: Date
    public let removedByDeviceID: RecordingDeviceID

    public init(
        id: UUID,
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
