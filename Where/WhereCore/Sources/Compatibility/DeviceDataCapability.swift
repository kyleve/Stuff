import Foundation

/// Operational metadata owned by one installation; never restored from a backup.
public struct DeviceDataCapability: Sendable, Hashable {
    public let deviceID: RecordingDeviceID
    public let supportedVersion: DataCompatibilityVersion
    public let revision: Int64
    public let reportedAt: Date

    public init(
        deviceID: RecordingDeviceID,
        supportedVersion: DataCompatibilityVersion,
        revision: Int64,
        reportedAt: Date,
    ) {
        precondition(revision >= 0)
        self.deviceID = deviceID
        self.supportedVersion = supportedVersion
        self.revision = revision
        self.reportedAt = reportedAt
    }

    /// The latest installation-owned revision wins, including a lower version after a downgrade.
    /// Conflicting equal revisions choose the less capable value conservatively.
    static func isOlder(_ lhs: Self, than rhs: Self) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.supportedVersion != rhs
            .supportedVersion { return lhs.supportedVersion > rhs.supportedVersion }
        return lhs.reportedAt < rhs.reportedAt
    }
}
