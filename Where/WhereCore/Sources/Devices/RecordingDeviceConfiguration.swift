import Foundation

/// One row shown by device-management UI: the synced profile plus its latest
/// desired policy and whether that policy has been acknowledged by the device.
public struct RecordingDeviceConfiguration: Identifiable, Sendable, Hashable {
    public let device: RecordingDevice
    public let isEnabled: Bool
    public let latestPolicyChangeID: UUID?

    public var id: RecordingDeviceID {
        device.id
    }

    public var isPending: Bool {
        guard let latestPolicyChangeID else { return false }
        return device.lastAppliedPolicyChangeID != latestPolicyChangeID
    }

    public init(
        device: RecordingDevice,
        isEnabled: Bool,
        latestPolicyChangeID: UUID?,
    ) {
        self.device = device
        self.isEnabled = isEnabled
        self.latestPolicyChangeID = latestPolicyChangeID
    }
}
