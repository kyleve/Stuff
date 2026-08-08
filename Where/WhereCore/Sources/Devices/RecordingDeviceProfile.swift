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
}
