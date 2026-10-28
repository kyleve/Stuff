import Foundation

/// Stable wire discriminator for a user-editable device-profile field.
public enum RecordingDeviceMetadataField: String, Codable, Sendable, Hashable {
    case nickname
}

/// One rename-safe metadata edit payload. The custom conformance keeps the persisted field
/// discriminator stable while making field-specific values impossible to combine incorrectly.
public enum RecordingDeviceMetadataPayload: Codable, Sendable, Hashable {
    /// New nickname; `nil` explicitly clears it.
    case nickname(String?)

    public var field: RecordingDeviceMetadataField {
        switch self {
            case .nickname: .nickname
        }
    }

    private enum CodingKeys: String, CodingKey {
        case field
        case nickname
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let field = try container.decode(RecordingDeviceMetadataField.self, forKey: .field)
        switch field {
            case .nickname:
                self = try .nickname(container.decodeIfPresent(String.self, forKey: .nickname))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(field, forKey: .field)
        switch self {
            case let .nickname(value):
                try container.encodeIfPresent(value, forKey: .nickname)
        }
    }
}

/// Append-only metadata edit for one recording installation.
///
/// Recording consent deliberately does not live here; it stays installation-local while
/// irreversible removal tombstones sync separately. The custom `Codable` conformance validates
/// the nonnegative revision before construction so a malformed archive throws instead of
/// tripping the initializer precondition.
public struct RecordingDeviceMetadataChange: Identifiable, Codable, Sendable, Hashable {
    /// Stable identity for one immutable metadata event.
    public struct ID: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(UUID.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public let id: ID
    public let deviceID: RecordingDeviceID
    public let revision: Int64
    public let changedAt: Date
    public let changedByDeviceID: RecordingDeviceID
    public let payload: RecordingDeviceMetadataPayload

    public var field: RecordingDeviceMetadataField {
        payload.field
    }

    public var nickname: String? {
        guard case let .nickname(value) = payload else { return nil }
        return value
    }

    public init(
        id: ID,
        deviceID: RecordingDeviceID,
        revision: Int64,
        changedAt: Date,
        changedByDeviceID: RecordingDeviceID,
        payload: RecordingDeviceMetadataPayload,
    ) {
        precondition(revision >= 0, "A recording-device metadata revision cannot be negative.")
        self.id = id
        self.deviceID = deviceID
        self.revision = revision
        self.changedAt = changedAt
        self.changedByDeviceID = changedByDeviceID
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case deviceID
        case revision
        case changedAt
        case changedByDeviceID
        case payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
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
        payload = try container.decode(RecordingDeviceMetadataPayload.self, forKey: .payload)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(revision, forKey: .revision)
        try container.encode(changedAt, forKey: .changedAt)
        try container.encode(changedByDeviceID, forKey: .changedByDeviceID)
        try container.encode(payload, forKey: .payload)
    }

    static func isOrderedBefore(
        _ lhs: RecordingDeviceMetadataChange,
        _ rhs: RecordingDeviceMetadataChange,
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    /// Stable winner when CloudKit supplies conflicting values for one immutable event id.
    /// Local writes reject this state, but reads must still converge on every device. The UUID is
    /// deliberately the final ordering key in ``isOrderedBefore``; it breaks revision ties only.
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
}
