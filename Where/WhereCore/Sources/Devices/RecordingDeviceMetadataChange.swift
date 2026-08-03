import Foundation

/// User-editable device-profile field changed by an append-only metadata event.
public enum RecordingDeviceMetadataField: String, Codable, Sendable, Hashable {
    case nickname
}

/// Append-only nickname edit for one recording installation.
///
/// Recording authority, including archive, deliberately does not live here: On, Off, and
/// archived are mutually exclusive states in the single ``RecordingPolicyChange`` stream.
public struct RecordingDeviceMetadataChange: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deviceID: RecordingDeviceID
    public let revision: Int64
    public let changedAt: Date
    public let changedByDeviceID: RecordingDeviceID
    /// New nickname; `nil` explicitly clears it.
    public let nickname: String?

    public var field: RecordingDeviceMetadataField {
        .nickname
    }

    public init(
        id: UUID,
        deviceID: RecordingDeviceID,
        revision: Int64,
        changedAt: Date,
        changedByDeviceID: RecordingDeviceID,
        nickname: String?,
    ) {
        precondition(revision >= 0, "A recording-device metadata revision cannot be negative.")
        self.id = id
        self.deviceID = deviceID
        self.revision = revision
        self.changedAt = changedAt
        self.changedByDeviceID = changedByDeviceID
        self.nickname = nickname
    }

    static func isOrderedBefore(
        _ lhs: RecordingDeviceMetadataChange,
        _ rhs: RecordingDeviceMetadataChange,
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Stable winner when CloudKit supplies conflicting values for one immutable event id.
    /// Local writes reject this state, but reads must still converge on every device.
    static func isCanonicalBefore(
        _ lhs: RecordingDeviceMetadataChange,
        _ rhs: RecordingDeviceMetadataChange,
    ) -> Bool {
        if lhs.deviceID != rhs.deviceID {
            return lhs.deviceID.storeURL.absoluteString < rhs.deviceID.storeURL.absoluteString
        }
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.changedAt != rhs.changedAt { return lhs.changedAt < rhs.changedAt }
        if lhs.changedByDeviceID != rhs.changedByDeviceID {
            return lhs.changedByDeviceID.storeURL.absoluteString
                < rhs.changedByDeviceID.storeURL.absoluteString
        }
        switch (lhs.nickname, rhs.nickname) {
            case (nil, .some): return true
            case (.some, nil): return false
            case let (.some(lhsNickname), .some(rhsNickname)):
                return lhsNickname < rhsNickname
            case (nil, nil): return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case deviceID
        case field
        case revision
        case changedAt
        case changedByDeviceID
        case nickname
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        deviceID = try container.decode(RecordingDeviceID.self, forKey: .deviceID)
        revision = try container.decode(Int64.self, forKey: .revision)
        guard revision >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .revision,
                in: container,
                debugDescription: "A recording-device metadata revision cannot be negative.",
            )
        }
        changedAt = try container.decode(Date.self, forKey: .changedAt)
        changedByDeviceID = try container.decode(
            RecordingDeviceID.self,
            forKey: .changedByDeviceID,
        )
        _ = try container.decode(RecordingDeviceMetadataField.self, forKey: .field)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(field, forKey: .field)
        try container.encode(revision, forKey: .revision)
        try container.encode(changedAt, forKey: .changedAt)
        try container.encode(changedByDeviceID, forKey: .changedByDeviceID)
        try container.encodeIfPresent(nickname, forKey: .nickname)
    }
}
