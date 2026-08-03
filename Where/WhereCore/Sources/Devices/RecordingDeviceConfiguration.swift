import Foundation

/// One installation row paired with the account-wide assignment resolution.
public struct RecordingDeviceConfiguration: Identifiable, Sendable, Hashable {
    public let device: RecordingDevice
    public let assignmentResolution: RecordingAssignmentResolution
    public let assignmentFrontierID: UUID?
    public let isAssignmentAcknowledged: Bool
    public let isArchived: Bool

    public var id: RecordingDeviceID {
        device.id
    }

    /// Whether this row is the one assigned recorder. Nil means authority is not safely resolved.
    public var isEnabled: Bool? {
        guard let assignment = assignmentResolution.assignment else { return nil }
        return assignment.deviceID == id
    }

    public var latestAssignmentChangeID: UUID? {
        assignmentFrontierID
    }

    public var isPending: Bool {
        guard assignmentResolution.assignment != nil else { return true }
        return isEnabled == true && isAssignmentAcknowledged == false
    }

    public init(
        device: RecordingDevice,
        assignmentResolution: RecordingAssignmentResolution,
        assignmentFrontierID: UUID?,
        isAssignmentAcknowledged: Bool,
        isArchived: Bool,
    ) {
        self.device = device
        self.assignmentResolution = assignmentResolution
        self.assignmentFrontierID = assignmentFrontierID
        self.isAssignmentAcknowledged = isAssignmentAcknowledged
        self.isArchived = isArchived
    }
}
