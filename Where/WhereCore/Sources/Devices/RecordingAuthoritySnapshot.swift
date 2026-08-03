/// Account-wide recording authority plus the installations that can be assigned.
public struct RecordingAuthoritySnapshot: Sendable, Hashable {
    public let resolution: RecordingAssignmentResolution
    public let devices: [RecordingDevice]
    public let archivedDeviceIDs: Set<RecordingDeviceID>

    public init(
        resolution: RecordingAssignmentResolution,
        devices: [RecordingDevice],
        archivedDeviceIDs: Set<RecordingDeviceID>,
    ) {
        self.resolution = resolution
        self.devices = devices
        self.archivedDeviceIDs = archivedDeviceIDs
    }
}
