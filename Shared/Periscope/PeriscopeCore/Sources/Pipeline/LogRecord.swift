import Foundation

/// One emitted log event with its context: the event value itself, when it
/// happened, and the scopes it belongs to.
///
/// Records carry the live `LogEvent` value — encoding to a persistable
/// payload happens later, in the store, off the caller's thread.
public struct LogRecord: Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let event: any LogEvent

    /// The scopes this record belongs to, primary first. Normally one; more
    /// when the emitting log was linked (`+`).
    public let scopes: [ScopeID]

    /// The tags the emitting context had accumulated (see `Log.tagged`).
    public let tags: [LogTagKey: String]

    /// Data attached at the call site (see `LogAttachment`).
    public let attachments: [LogAttachment]

    /// Skips the recorder's level floors on delivery. Span lifecycle
    /// records set this: the floor decision is made once, at `begin`, and
    /// the whole pair follows it — a recorded began must get its end even
    /// if floors rose mid-span (see `Log.begin`).
    var bypassesFloors = false

    public init(
        id: UUID = UUID(),
        date: Date,
        event: any LogEvent,
        scopes: [ScopeID],
        tags: [LogTagKey: String] = [:],
        attachments: [LogAttachment] = [],
    ) {
        self.id = id
        self.date = date
        self.event = event
        self.scopes = scopes
        self.tags = tags
        self.attachments = attachments
    }

    public var level: LogLevel {
        event.level
    }

    public var message: String {
        event.message
    }

    public var eventName: String {
        type(of: event).eventName
    }

    public var eventVersion: Int {
        type(of: event).eventVersion
    }
}
