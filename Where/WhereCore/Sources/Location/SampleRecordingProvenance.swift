import Foundation

/// Installation attribution, with a tenure only for samples accepted under recording authority.
/// A nil tenure retains pre-contract history without inventing an automatic recording grant.
public struct SampleRecordingProvenance: Codable, Hashable, Sendable {
    public let deviceID: RecordingDeviceID
    public let tenureID: RecordingAuthority.EventID?

    public init(deviceID: RecordingDeviceID, tenureID: RecordingAuthority.EventID?) {
        self.deviceID = deviceID
        self.tenureID = tenureID
    }
}
