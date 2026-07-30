import Foundation

/// Append-only change to automatic recording policy for one device.
///
/// The timestamp is the effective historical cutoff. A device that has not
/// received the CloudKit change may briefly keep producing raw samples, but
/// every report filters those samples from this instant onward.
public struct RecordingPolicyChange: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deviceID: RecordingDeviceID
    public let effectiveAt: Date
    public let isEnabled: Bool

    public init(
        id: UUID,
        deviceID: RecordingDeviceID,
        effectiveAt: Date,
        isEnabled: Bool,
    ) {
        self.id = id
        self.deviceID = deviceID
        self.effectiveAt = effectiveAt
        self.isEnabled = isEnabled
    }
}

extension RecordingPolicyChange {
    /// Deterministic latest-wins ordering. UUID text breaks equal-timestamp
    /// ties so devices that receive concurrent CloudKit rows converge.
    static func isOrderedBefore(
        _ lhs: RecordingPolicyChange,
        _ rhs: RecordingPolicyChange,
    ) -> Bool {
        if lhs.effectiveAt != rhs.effectiveAt {
            return lhs.effectiveAt < rhs.effectiveAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
