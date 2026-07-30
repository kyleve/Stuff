import Foundation

/// Broad hardware family used to choose an icon without persisting a
/// user-visible device name supplied by the operating system.
public enum RecordingDeviceKind: String, Codable, Sendable, Hashable {
    case phone
    case tablet
    case other
}

/// The last effective recording state acknowledged by a device.
public enum RecordingDeviceStatus: String, Codable, Sendable, Hashable {
    case recording
    case off
    case permissionRequired
}

/// Synced profile for one device that can contribute automatic locations.
///
/// `nickname` is user-editable and synced. `systemName` is only a generic
/// hardware label such as “iPhone” or “iPad”; Where deliberately does not ask
/// for the user-assigned-device-name entitlement.
public struct RecordingDevice: Identifiable, Codable, Sendable, Hashable {
    public let id: RecordingDeviceID
    public let systemName: String
    public let nickname: String?
    public let kind: RecordingDeviceKind
    public let registeredAt: Date
    public let lastSeenAt: Date
    public let archivedAt: Date?
    public let lastAppliedPolicyChangeID: UUID?
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
        self.status = status
    }

    public var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        return if let trimmed, !trimmed.isEmpty { trimmed } else { systemName }
    }

    func renamed(_ nickname: String?) -> RecordingDevice {
        RecordingDevice(
            id: id,
            systemName: systemName,
            nickname: nickname,
            kind: kind,
            registeredAt: registeredAt,
            lastSeenAt: lastSeenAt,
            archivedAt: archivedAt,
            lastAppliedPolicyChangeID: lastAppliedPolicyChangeID,
            status: status,
        )
    }

    func archived(at date: Date) -> RecordingDevice {
        RecordingDevice(
            id: id,
            systemName: systemName,
            nickname: nickname,
            kind: kind,
            registeredAt: registeredAt,
            lastSeenAt: lastSeenAt,
            archivedAt: date,
            lastAppliedPolicyChangeID: lastAppliedPolicyChangeID,
            status: status,
        )
    }

    func unarchived() -> RecordingDevice {
        RecordingDevice(
            id: id,
            systemName: systemName,
            nickname: nickname,
            kind: kind,
            registeredAt: registeredAt,
            lastSeenAt: lastSeenAt,
            archivedAt: nil,
            lastAppliedPolicyChangeID: lastAppliedPolicyChangeID,
            status: status,
        )
    }

    func acknowledging(
        policyChangeID: UUID,
        status: RecordingDeviceStatus,
        at date: Date,
    ) -> RecordingDevice {
        RecordingDevice(
            id: id,
            systemName: systemName,
            nickname: nickname,
            kind: kind,
            registeredAt: registeredAt,
            lastSeenAt: date,
            archivedAt: archivedAt,
            lastAppliedPolicyChangeID: policyChangeID,
            status: status,
        )
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
    public static let preview = CurrentRecordingDevice(
        id: RecordingDeviceID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        ),
        systemName: "iPhone",
        kind: .phone,
    )
}
