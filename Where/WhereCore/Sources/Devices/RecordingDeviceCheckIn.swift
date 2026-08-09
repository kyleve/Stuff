import Foundation

/// Latest recording state and activity heartbeat written by one installation.
///
/// The target installation is the sole live writer for its check-in. Keeping this row apart
/// from user-editable metadata prevents a local acknowledgement from reverting a remote rename
/// or another installation's recording consent, and vice versa.
public struct RecordingDeviceCheckIn: Identifiable, Codable, Sendable, Hashable {
    public var id: RecordingDeviceID {
        deviceID
    }

    public let deviceID: RecordingDeviceID
    /// Monotonic sequence written only by the target installation.
    public let revision: Int64
    public let lastSeenAt: Date
    public let status: RecordingDeviceStatus

    public init(
        deviceID: RecordingDeviceID,
        revision: Int64,
        lastSeenAt: Date,
        status: RecordingDeviceStatus,
    ) {
        precondition(revision >= 0, "A recording-device check-in revision cannot be negative.")
        precondition(status != .unknown, "A persisted device check-in must have a known status.")
        self.deviceID = deviceID
        self.revision = revision
        self.lastSeenAt = lastSeenAt
        self.status = status
    }

    static func isOlder(_ lhs: RecordingDeviceCheckIn, than rhs: RecordingDeviceCheckIn) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        if lhs.lastSeenAt != rhs.lastSeenAt {
            return lhs.lastSeenAt < rhs.lastSeenAt
        }
        return lhs.status.rawValue < rhs.status.rawValue
    }
}
