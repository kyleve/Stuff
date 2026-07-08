import Foundation

/// Filters for `PeriscopeStore` event queries. Unset fields don't filter;
/// set fields combine with AND.
///
/// ```swift
/// var query = LogQuery()
/// query.minimumLevel = .warning
/// query.scope = .subtree(photosLog.primaryScope.id)
/// query.limit = 100
/// let events = try await store.events(matching: query)   // newest first
/// ```
public struct LogQuery: Sendable {
    /// Only events at or after this date.
    public var start: Date?
    /// Only events at or before this date.
    public var end: Date?
    /// Only events at this severity or above.
    public var minimumLevel: LogLevel?
    /// Only events persisted under this exact event name.
    public var eventName: String?
    /// Only events from this session (launch).
    public var sessionID: UUID?
    /// Only events referencing the given scope — exactly, or anywhere in
    /// its subtree.
    public var scope: ScopeFilter?
    /// Only events stamped with this exact key/value tag.
    public var tag: LogTag?
    /// Only events whose message matches this text
    /// (`localizedStandardContains`).
    public var messageContains: String?
    /// Page size; unset fetches everything that matches.
    public var limit: Int?
    /// Page offset into the newest-first ordering.
    public var offset: Int?

    public init() {}
}

/// How a query matches an event's scopes.
public enum ScopeFilter: Hashable, Sendable {
    /// The event references exactly this scope.
    case exactly(ScopeID)
    /// The event references this scope or any of its descendants.
    case subtree(ScopeID)
}
