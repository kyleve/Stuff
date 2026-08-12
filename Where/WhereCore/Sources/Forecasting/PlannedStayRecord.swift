import Foundation

/// One revision of the single synced planned-stay register. A `nil` value is a
/// tombstone, retained so a delayed CloudKit import cannot resurrect an older
/// active stay after it was cleared or expired.
public struct PlannedStayRecord: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let value: PlannedStay?
    public let updatedAt: Date

    public init(id: UUID, value: PlannedStay?, updatedAt: Date) {
        self.id = id
        self.value = value
        self.updatedAt = updatedAt
    }

    /// Deterministic last-writer ordering for duplicate rows produced by
    /// eventually-consistent CloudKit writes.
    public static func newer(_ lhs: PlannedStayRecord, than rhs: PlannedStayRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
