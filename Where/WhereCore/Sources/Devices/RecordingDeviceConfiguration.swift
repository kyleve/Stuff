import Foundation

/// One synced device row plus the local preference available only for this installation.
public struct RecordingDeviceConfiguration: Identifiable, Sendable, Hashable {
    public let device: RecordingDevice
    public let isCurrentDevice: Bool
    public let localAutomaticRecordingEnabled: Bool?

    public var id: RecordingDeviceID {
        device.id
    }

    public var isRemoved: Bool {
        device.removedAt != nil
    }

    public init(
        device: RecordingDevice,
        isCurrentDevice: Bool,
        localAutomaticRecordingEnabled: Bool?,
    ) {
        precondition(
            isCurrentDevice || localAutomaticRecordingEnabled == nil,
            "A remote device cannot expose another installation's local preference.",
        )
        self.device = device
        self.isCurrentDevice = isCurrentDevice
        self.localAutomaticRecordingEnabled = localAutomaticRecordingEnabled
    }
}
