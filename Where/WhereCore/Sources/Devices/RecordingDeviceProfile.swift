import Foundation

/// Immutable synced identity for one installation that can contribute automatic locations.
///
/// Only the installation itself creates this value. User-editable labels, archive state,
/// and the installation's acknowledgement heartbeat live in separate records so CloudKit
/// never has two devices overwriting unrelated fields on one row.
public struct RecordingDeviceProfile: Identifiable, Codable, Sendable, Hashable {
    public let id: RecordingDeviceID
    public let systemName: String
    public let kind: RecordingDeviceKind
    public let registeredAt: Date
    /// Logical account generation in which this installation first registered. A profile is
    /// global and survives later rotations; this origin lets the target distinguish an
    /// interrupted first registration from an old installation entering a new generation.
    public let registrationGenerationID: WhereDataGenerationID

    public init(
        id: RecordingDeviceID,
        systemName: String,
        kind: RecordingDeviceKind,
        registeredAt: Date,
        registrationGenerationID: WhereDataGenerationID,
    ) {
        self.id = id
        self.systemName = systemName
        self.kind = kind
        self.registeredAt = registeredAt
        self.registrationGenerationID = registrationGenerationID
    }

    /// Stable winner when CloudKit supplies conflicting immutable rows for one profile id.
    static func isCanonicalBefore(
        _ lhs: RecordingDeviceProfile,
        _ rhs: RecordingDeviceProfile,
    ) -> Bool {
        if lhs.registeredAt != rhs.registeredAt { return lhs.registeredAt < rhs.registeredAt }
        if lhs.systemName != rhs.systemName { return lhs.systemName < rhs.systemName }
        if lhs.kind.persistenceDiscriminator != rhs.kind.persistenceDiscriminator {
            return lhs.kind.persistenceDiscriminator < rhs.kind.persistenceDiscriminator
        }
        switch (lhs.kind.persistenceDetail, rhs.kind.persistenceDetail) {
            case (nil, .some): return true
            case (.some, nil): return false
            case let (.some(lhsDetail), .some(rhsDetail)) where lhsDetail != rhsDetail:
                return lhsDetail < rhsDetail
            case (.some, .some), (nil, nil): break
        }
        return lhs.registrationGenerationID.rawValue.uuidString
            < rhs.registrationGenerationID.rawValue.uuidString
    }
}
