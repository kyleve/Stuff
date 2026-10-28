import Foundation

/// A persisted dismissal of a data-resolution issue: the typed identity the
/// user dismissed (`DataIssueID`) plus when they dismissed it.
///
/// Crosses the `WhereStore` boundary as a value type — callers never touch the
/// SwiftData record — and is `Codable` so the whole-database backup can
/// round-trip a dismissal verbatim (id *and* timestamp), keeping issues the
/// user already dismissed dismissed after a restore. `DataIssueID` encodes as
/// its `store://` URL, so a dismissal serializes as
/// `{"id":"store://issues/…","dismissedAt":…}`.
public struct DismissedIssue: Codable, Sendable, Hashable {
    /// The typed identity of the dismissed issue.
    public let id: DataIssueID
    /// When the user dismissed the issue.
    public let dismissedAt: Date

    public init(id: DataIssueID, dismissedAt: Date) {
        self.id = id
        self.dismissedAt = dismissedAt
    }
}
