import Foundation

/// Installation attribution and the optional ownership ID from automatic recording.
/// A nil `ownershipID` retains pre-contract history without inventing a recording grant.
public struct SampleRecordingProvenance: Codable, Hashable, Sendable {
    public let deviceID: RecordingDeviceID
    public let ownershipID: RecordingAuthority.EventID?

    public init(deviceID: RecordingDeviceID, ownershipID: RecordingAuthority.EventID?) {
        self.deviceID = deviceID
        self.ownershipID = ownershipID
    }
}
