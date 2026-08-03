import Foundation

/// Resolved desired policy for one device.
public struct ResolvedRecordingPolicy: Sendable, Hashable {
    public let isEnabled: Bool
    public let isArchived: Bool
    public let changeID: UUID
    public let isAcknowledged: Bool

    public init(
        isEnabled: Bool,
        isArchived: Bool,
        changeID: UUID,
        isAcknowledged: Bool,
    ) {
        self.isEnabled = isEnabled
        self.isArchived = isArchived
        self.changeID = changeID
        self.isAcknowledged = isAcknowledged
    }
}
