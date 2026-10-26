import Foundation

/// Automatic-sample attribution. Legacy device attribution does not imply an ownership grant.
/// This domain value is not serialized; LocationSample retains its existing optional wire fields.
public enum SampleRecordingProvenance: Hashable, Sendable {
    case legacy(deviceID: RecordingDeviceID)
    case owned(RecordingAuthority.Owner)

    public var deviceID: RecordingDeviceID {
        switch self {
            case let .legacy(deviceID): deviceID
            case let .owned(owner): owner.deviceID
        }
    }

    public var ownershipID: RecordingAuthority.OwnershipID? {
        switch self {
            case .legacy: nil
            case let .owned(owner): owner.ownershipID
        }
    }
}
