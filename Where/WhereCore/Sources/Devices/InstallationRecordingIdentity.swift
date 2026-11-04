import Foundation

/// Device-only identity that can survive same-device reinstall independently of local consent.
/// The creation reason lets sidecar recovery distinguish reset from rejoin after an interrupted
/// write.
public struct InstallationRecordingIdentity: Hashable, Sendable, Codable {
    public enum Creation: String, Hashable, Sendable, Codable {
        case initial
        case reset
        case rejoin
    }

    public let deviceID: RecordingDeviceID
    public let registeredAt: Date
    public let creation: Creation

    public init(deviceID: RecordingDeviceID, registeredAt: Date, creation: Creation) {
        self.deviceID = deviceID
        self.registeredAt = registeredAt
        self.creation = creation
    }
}
