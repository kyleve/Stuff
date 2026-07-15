import Foundation

/// The synthetic event `PeriscopeStore` persists after a failed,
/// rolled-back write — the durable history's marker for its own gap.
/// The lost batch's contents are gone by definition; this records how
/// many records vanished and why.
public struct StoreWriteFailed: LogEvent {
    public static let eventName = "store-write-failed"

    public let lostRecordCount: Int
    public let reason: String

    public var level: LogLevel {
        .warning
    }

    public var message: String {
        "\(lostRecordCount) record(s) failed to persist: \(reason)"
    }

    public init(lostRecordCount: Int, reason: String) {
        self.lostRecordCount = lostRecordCount
        self.reason = reason
    }
}

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
    /// Store-assigned monotonic insertion order — the tiebreak when two
    /// events share a date, so merged query results sort stably.
    public let sequence: Int
    public let level: LogLevel
    public let eventName: String
    public let eventVersion: Int
    public let message: String
    /// The event's stored properties, JSON-encoded.
    public let payload: Data
    /// Every scope the event references, primary first, in emission order.
    public let scopes: [ScopeID]
    /// The tags the event was stamped with.
    public let tags: [LogTag]
    /// The span this event begins or ends, when it is a span event.
    public let spanID: SpanID?
    /// How the span ended, when this is a span-ended event (the reason
    /// lives in the payload — decode `SpanEnded` for it).
    public let spanExitMode: SpanExit.Mode?
    /// The emitting function/file, when the call site captured one.
    public let callSite: LogCallSite?
    /// The event's associated-object identifier (`LogEvent.externalID`).
    public let externalID: String?
    /// Attachment metadata; bytes load via
    /// `PeriscopeStore.attachments(forEvent:)`.
    public let attachments: [LogAttachmentInfo]
    public let sessionID: UUID

    public init(
        id: UUID,
        date: Date,
        sequence: Int,
        level: LogLevel,
        eventName: String,
        eventVersion: Int,
        message: String,
        payload: Data,
        scopes: [ScopeID],
        tags: [LogTag],
        spanID: SpanID?,
        spanExitMode: SpanExit.Mode?,
        callSite: LogCallSite?,
        externalID: String?,
        attachments: [LogAttachmentInfo],
        sessionID: UUID,
    ) {
        self.id = id
        self.date = date
        self.sequence = sequence
        self.level = level
        self.eventName = eventName
        self.eventVersion = eventVersion
        self.message = message
        self.payload = payload
        self.scopes = scopes
        self.tags = tags
        self.spanID = spanID
        self.spanExitMode = spanExitMode
        self.callSite = callSite
        self.externalID = externalID
        self.attachments = attachments
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
