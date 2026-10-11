import Foundation

/// Installation attribution, with an ownership period only for samples accepted under recording
/// authority.
/// A nil ownership period retains pre-contract history without inventing an automatic recording
/// grant.
public struct SampleRecordingProvenance: Codable, Hashable, Sendable {
    public let deviceID: RecordingDeviceID
    public let ownershipID: RecordingAuthority.EventID?

    public init(deviceID: RecordingDeviceID, ownershipID: RecordingAuthority.EventID?) {
        self.deviceID = deviceID
        self.ownershipID = ownershipID
    }
}
