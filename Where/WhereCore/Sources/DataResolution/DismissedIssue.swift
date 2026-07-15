import Foundation

/// A persisted dismissal of a data-resolution issue: the stable key the user
/// dismissed (`DataIssueID.storageKey`) plus when they dismissed it.
///
/// Crosses the `WhereStore` boundary as a value type — callers never touch the
/// SwiftData record — and is `Codable` so the whole-database backup can
/// round-trip a dismissal verbatim (key *and* timestamp), keeping issues the
/// user already dismissed dismissed after a restore.
public struct DismissedIssue: Codable, Sendable, Hashable {
    /// Stable, device-independent identity of the dismissed issue
    /// (`DataIssueID.storageKey`).
    public let key: String
    /// When the user dismissed the issue.
    public let dismissedAt: Date

    public init(key: String, dismissedAt: Date) {
        self.key = key
        self.dismissedAt = dismissedAt
    }
}
