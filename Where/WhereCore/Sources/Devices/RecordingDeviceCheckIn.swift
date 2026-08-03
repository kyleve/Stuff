import Foundation

/// Stable proof key for the destructive policy frontier whose outbox cleanup completed.
///
/// A single barrier uses its event id; concurrent barriers use a deterministic digest of every
/// frontier event id, so this is deliberately not modeled as one policy-change identity.
struct RecordingPolicyCleanupToken: RawRepresentable, Hashable {
    let rawValue: UUID
}

/// Latest policy acknowledgement and activity heartbeat written by one installation.
///
/// The target installation is the sole live writer for its check-in. Keeping this row apart
/// from user-editable metadata prevents a local acknowledgement from reverting a remote rename
/// or recording authority, and vice versa.
public struct RecordingDeviceCheckIn: Identifiable, Codable, Sendable, Hashable {
    public var id: RecordingDeviceID {
        deviceID
    }

    public let deviceID: RecordingDeviceID
    /// Monotonic sequence written only by the target installation.
    public let revision: Int64
    public let lastSeenAt: Date
    public let appliedAt: Date
    public let lastAppliedPolicyChangeID: UUID
    /// Persisted UUID backing the destructive-frontier cleanup proof. It is an event id for a
    /// singleton frontier and a deterministic digest for concurrent barriers. The legacy storage
    /// name remains stable; domain code uses ``lastDiscardedPolicyFrontierToken``.
    public let lastDiscardedPolicyChangeID: UUID?

    var lastDiscardedPolicyFrontierToken: RecordingPolicyCleanupToken? {
        lastDiscardedPolicyChangeID.map(RecordingPolicyCleanupToken.init(rawValue:))
    }

    public let status: RecordingDeviceStatus

    public init(
        deviceID: RecordingDeviceID,
        revision: Int64,
        lastSeenAt: Date,
        appliedAt: Date,
        lastAppliedPolicyChangeID: UUID,
        status: RecordingDeviceStatus,
    ) {
        precondition(revision >= 0, "A recording-device check-in revision cannot be negative.")
        precondition(status != .unknown, "A persisted device check-in must have a known status.")
        self.deviceID = deviceID
        self.revision = revision
        self.lastSeenAt = lastSeenAt
        self.appliedAt = appliedAt
        self.lastAppliedPolicyChangeID = lastAppliedPolicyChangeID
        lastDiscardedPolicyChangeID = nil
        self.status = status
    }

    init(
        deviceID: RecordingDeviceID,
        revision: Int64,
        lastSeenAt: Date,
        appliedAt: Date,
        lastAppliedPolicyChangeID: UUID,
        lastDiscardedPolicyFrontierToken: RecordingPolicyCleanupToken?,
        status: RecordingDeviceStatus,
    ) {
        precondition(revision >= 0, "A recording-device check-in revision cannot be negative.")
        precondition(status != .unknown, "A persisted device check-in must have a known status.")
        self.deviceID = deviceID
        self.revision = revision
        self.lastSeenAt = lastSeenAt
        self.appliedAt = appliedAt
        self.lastAppliedPolicyChangeID = lastAppliedPolicyChangeID
        lastDiscardedPolicyChangeID = lastDiscardedPolicyFrontierToken?.rawValue
        self.status = status
    }

    static func isOlder(_ lhs: RecordingDeviceCheckIn, than rhs: RecordingDeviceCheckIn) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        if lhs.lastAppliedPolicyChangeID != rhs.lastAppliedPolicyChangeID {
            return lhs.lastAppliedPolicyChangeID.uuidString
                < rhs.lastAppliedPolicyChangeID.uuidString
        }
        if lhs.lastDiscardedPolicyChangeID != rhs.lastDiscardedPolicyChangeID {
            return (lhs.lastDiscardedPolicyChangeID?.uuidString ?? "")
                < (rhs.lastDiscardedPolicyChangeID?.uuidString ?? "")
        }
        if lhs.appliedAt != rhs.appliedAt {
            return lhs.appliedAt < rhs.appliedAt
        }
        if lhs.lastSeenAt != rhs.lastSeenAt {
            return lhs.lastSeenAt < rhs.lastSeenAt
        }
        return lhs.status.rawValue < rhs.status.rawValue
    }
}
