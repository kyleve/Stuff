import Foundation

/// The issue, timestamp, and installation associated with a retained dismissal.
/// Backups preserve all three fields. The issue ID encodes as its `store://` URL.
public struct DismissedIssue: Codable, Sendable, Hashable {
    /// The typed identity of the dismissed issue.
    public let id: DataIssueID
    /// When the user dismissed the issue.
    public let dismissedAt: Date
    /// Installation that dismissed the issue.
    public let dismissedByDeviceID: RecordingDeviceID

    public init(id: DataIssueID, dismissedAt: Date, dismissedByDeviceID: RecordingDeviceID) {
        self.id = id
        self.dismissedAt = dismissedAt
        self.dismissedByDeviceID = dismissedByDeviceID
    }
}
