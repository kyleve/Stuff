import Foundation

/// Broad hardware family used to choose an icon without persisting a
/// user-visible device name supplied by the operating system.
public enum RecordingDeviceKind: String, Codable, Sendable, Hashable {
    case phone
    case tablet
    case other

    /// Safe first-run recommendation for automatic recording. A phone usually
    /// travels with its owner; tablets and other devices are commonly left
    /// behind and must be opted in explicitly.
    public var recommendsAutomaticRecording: Bool {
        switch self {
            case .phone: true
            case .tablet, .other: false
        }
    }
}

/// The last effective recording state acknowledged by a device.
public enum RecordingDeviceStatus: String, Codable, Sendable, Hashable {
    /// The profile arrived before this installation's first check-in.
    case unknown
    case recording
    case off
    case permissionRequired
}

/// Read model for one device assembled from independently synced records.
///
/// The immutable profile, append-only nickname timeline, desired-authority timeline, and
/// target-owned check-in have
/// deliberately separate persistence rows. This aggregate is never written back wholesale:
/// doing so would let CloudKit's last writer overwrite fields owned by another device.
public struct RecordingDevice: Identifiable, Codable, Sendable, Hashable {
    public let id: RecordingDeviceID
    public let systemName: String
    public let nickname: String?
    public let kind: RecordingDeviceKind
    public let registeredAt: Date
    public let lastSeenAt: Date
    public let archivedAt: Date?
    public let lastAppliedPolicyChangeID: UUID?
    /// Stable storage field; see `RecordingDeviceCheckIn.lastDiscardedPolicyChangeID`.
    public let lastDiscardedPolicyChangeID: UUID?

    var lastDiscardedPolicyFrontierToken: RecordingPolicyCleanupToken? {
        lastDiscardedPolicyChangeID.map(RecordingPolicyCleanupToken.init(rawValue:))
    }

    public let status: RecordingDeviceStatus

    public init(
        id: RecordingDeviceID,
        systemName: String,
        nickname: String?,
        kind: RecordingDeviceKind,
        registeredAt: Date,
        lastSeenAt: Date,
        archivedAt: Date?,
        lastAppliedPolicyChangeID: UUID?,
        status: RecordingDeviceStatus,
    ) {
        self.id = id
        self.systemName = systemName
        self.nickname = nickname
        self.kind = kind
        self.registeredAt = registeredAt
        self.lastSeenAt = lastSeenAt
        self.archivedAt = archivedAt
        self.lastAppliedPolicyChangeID = lastAppliedPolicyChangeID
        lastDiscardedPolicyChangeID = nil
        self.status = status
    }

    public var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        return if let trimmed, !trimmed.isEmpty { trimmed } else { systemName }
    }

    init(
        profile: RecordingDeviceProfile,
        nicknameChange: RecordingDeviceMetadataChange?,
        checkIn: RecordingDeviceCheckIn?,
        policyChange: RecordingPolicyChange?,
    ) {
        id = profile.id
        systemName = profile.systemName
        nickname = nicknameChange?.nickname
        kind = profile.kind
        registeredAt = profile.registeredAt
        lastSeenAt = checkIn?.lastSeenAt ?? profile.registeredAt
        archivedAt = policyChange?.isArchived == true ? policyChange?.effectiveAt : nil
        lastAppliedPolicyChangeID = checkIn?.lastAppliedPolicyChangeID
        lastDiscardedPolicyChangeID = checkIn?.lastDiscardedPolicyChangeID
        status = checkIn?.status ?? .unknown
    }
}

/// Local, non-synced description used to register this installation in the
/// synced device list.
public struct CurrentRecordingDevice: Sendable, Hashable {
    public let id: RecordingDeviceID
    public let systemName: String
    public let kind: RecordingDeviceKind

    public init(id: RecordingDeviceID, systemName: String, kind: RecordingDeviceKind) {
        self.id = id
        self.systemName = systemName
        self.kind = kind
    }

    /// Deterministic identity for tests and previews that do not care which
    /// installation is current.
    @_spi(Testing)
    public static let preview = CurrentRecordingDevice(
        id: RecordingDeviceID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        ),
        systemName: "iPhone",
        kind: .phone,
    )
}
