import Foundation

/// One revision of one stay. A retained nil value prevents delayed sync from
/// resurrecting that stay without replacing independently edited plans.
public struct PlannedStayRecord: Hashable, Sendable, Codable, Identifiable {
    public enum ValidationError: Error, Equatable {
        case mismatchedStayID
    }

    public let id: UUID
    public let stayID: PlannedStay.ID
    public let value: PlannedStay?
    public let changedByDeviceID: RecordingDeviceID
    public let updatedAt: Date

    public init(
        id: UUID,
        stayID: PlannedStay.ID,
        value: PlannedStay?,
        updatedAt: Date,
        changedByDeviceID: RecordingDeviceID,
    ) throws {
        self.id = id
        self.stayID = stayID
        self.value = value
        self.updatedAt = updatedAt
        self.changedByDeviceID = changedByDeviceID
        try validate()
    }

    func hasSamePortableValue(as other: Self) -> Bool {
        id == other.id && stayID == other.stayID && value == other
            .value && changedByDeviceID == other.changedByDeviceID
            && updatedAt.timeIntervalSince1970 == other.updatedAt.timeIntervalSince1970
    }

    /// Validate current-format identity and date invariants after synthesized decoding.
    public func validate() throws {
        guard let value else { return }
        guard value.id == stayID else { throw ValidationError.mismatchedStayID }
        try value.validate()
    }

    /// Deterministic last-writer ordering for duplicate rows produced by
    /// eventually-consistent CloudKit writes.
    public static func newer(_ lhs: PlannedStayRecord, than rhs: PlannedStayRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
