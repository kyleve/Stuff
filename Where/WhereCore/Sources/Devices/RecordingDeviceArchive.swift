import Foundation

/// Irreversible, append-only tombstone hiding an installation from active device UI.
public struct RecordingDeviceArchive: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deviceID: RecordingDeviceID
    public let archivedAt: Date
    public let archivedByDeviceID: RecordingDeviceID

    public init(
        id: UUID,
        deviceID: RecordingDeviceID,
        archivedAt: Date,
        archivedByDeviceID: RecordingDeviceID,
    ) {
        self.id = id
        self.deviceID = deviceID
        self.archivedAt = archivedAt
        self.archivedByDeviceID = archivedByDeviceID
    }
}
