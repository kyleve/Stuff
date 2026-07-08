import Foundation

/// A persisted log event, as returned by `PeriscopeStore` queries — the
/// value-type snapshot of a stored row.
///
/// The structured payload is retained as JSON keyed by ``eventName`` +
/// ``eventVersion``: ``decode(_:)`` recovers the original event type when it
/// still matches, and tooling can fall back to rendering ``payload`` as raw
/// JSON when the type has changed or no longer exists.
public struct StoredLogEvent: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let date: Date
    public let level: LogLevel
    public let eventName: String
    public let eventVersion: Int
    public let message: String
    /// The event's stored properties, JSON-encoded.
    public let payload: Data
    /// Every scope the event references, primary first, in emission order.
    public let scopes: [ScopeID]
    public let sessionID: UUID

    public init(
        id: UUID,
        date: Date,
        level: LogLevel,
        eventName: String,
        eventVersion: Int,
        message: String,
        payload: Data,
        scopes: [ScopeID],
        sessionID: UUID,
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.eventName = eventName
        self.eventVersion = eventVersion
        self.message = message
        self.payload = payload
        self.scopes = scopes
        self.sessionID = sessionID
    }

    public var primaryScope: ScopeID? {
        scopes.first
    }

    /// Decode the structured payload back to its event type. Throws when
    /// the stored JSON no longer matches the type's shape — callers degrade
    /// to ``payload`` / ``message`` rather than losing the row.
    public func decode<Event: LogEvent>(_: Event.Type) throws -> Event {
        try JSONDecoder().decode(Event.self, from: payload)
    }
}
