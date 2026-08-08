import Foundation

/// Broad hardware family used to choose an icon, with an optional stable platform label for
/// hardware the current build does not recognize explicitly.
public enum RecordingDeviceKind: Codable, Sendable, Hashable {
    case phone
    case tablet
    case computer
    case watch
    case other(String?)

    /// Safe first-run recommendation for automatic recording. A phone usually
    /// travels with its owner; tablets and other devices are commonly left
    /// behind and must be opted in explicitly.
    public var recommendsAutomaticRecording: Bool {
        switch self {
            case .phone: true
            case .tablet, .computer, .watch, .other: false
        }
    }

    var persistenceDiscriminator: String {
        switch self {
            case .phone: "phone"
            case .tablet: "tablet"
            case .computer: "computer"
            case .watch: "watch"
            case .other: "other"
        }
    }

    var persistenceDetail: String? {
        guard case let .other(detail) = self else { return nil }
        return detail
    }

    init?(persistenceDiscriminator: String, detail: String?) {
        switch persistenceDiscriminator {
            case "phone": self = .phone
            case "tablet": self = .tablet
            case "computer": self = .computer
            case "watch": self = .watch
            case "other": self = .other(detail)
            default: return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case detail
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let discriminator = try container.decode(String.self, forKey: .kind)
        let detail = try container.decodeIfPresent(String.self, forKey: .detail)
        guard let value = Self(
            persistenceDiscriminator: discriminator,
            detail: detail,
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown recording-device kind \(discriminator).",
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(persistenceDiscriminator, forKey: .kind)
        try container.encodeIfPresent(persistenceDetail, forKey: .detail)
    }
}

/// The latest advisory recording status reported by a device.
public enum RecordingDeviceStatus: String, Codable, Sendable, Hashable {
    /// The profile arrived before this installation's first check-in.
    case unknown
    case recording
    case off
    case permissionRequired
}

/// Read model for one device assembled from independently synced records.
///
/// The immutable profile, append-only nickname timeline, removal tombstone, and target-owned
/// check-in have deliberately separate persistence rows. This aggregate is never written back
/// wholesale:
/// doing so would let CloudKit's last writer overwrite fields owned by another device.
public struct RecordingDevice: Identifiable, Codable, Sendable, Hashable {
    public let id: RecordingDeviceID
    /// Hardware-family fallback captured at registration (for example “iPhone” or “iPad”), not
    /// the user's device name. `nickname` is the synced user-editable display name.
    public let systemName: String
    public let nickname: String?
    public let kind: RecordingDeviceKind
    public let registeredAt: Date
    public let lastSeenAt: Date
    public let removedAt: Date?

    public let status: RecordingDeviceStatus

    public init(
        id: RecordingDeviceID,
        systemName: String,
        nickname: String?,
        kind: RecordingDeviceKind,
        registeredAt: Date,
        lastSeenAt: Date,
        removedAt: Date?,
        status: RecordingDeviceStatus,
    ) {
        self.id = id
        self.systemName = systemName
        self.nickname = nickname
        self.kind = kind
        self.registeredAt = registeredAt
        self.lastSeenAt = lastSeenAt
        self.removedAt = removedAt
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
        removal: RecordingDeviceRemoval?,
    ) {
        id = profile.id
        systemName = profile.systemName
        nickname = nicknameChange?.nickname
        kind = profile.kind
        registeredAt = profile.registeredAt
        lastSeenAt = checkIn?.lastSeenAt ?? profile.registeredAt
        removedAt = removal?.removedAt
        status = checkIn?.status ?? .unknown
    }
}

/// Local, non-synced description used to register this installation in the
/// synced device list.
public struct CurrentRecordingDevice: Sendable, Hashable {
    public let id: RecordingDeviceID
    /// Hardware-family fallback supplied by the platform composition boundary.
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
