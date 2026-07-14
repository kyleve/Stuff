import Foundation

/// Where an event was emitted: the calling function and file, captured
/// via `#function`/`#fileID` defaults at the log call site.
public struct LogCallSite: Hashable, Codable, Sendable {
    /// E.g. `"uploadPhoto(_:)"`.
    public let function: String
    /// E.g. `"Where/PhotoUploader.swift"`.
    public let fileID: String

    public init(function: StaticString, fileID: StaticString) {
        self.function = String(describing: function)
        self.fileID = String(describing: fileID)
    }

    public init(function: String, fileID: String) {
        self.function = function
        self.fileID = fileID
    }

    /// Display form: `"PhotoUploader.swift · uploadPhoto(_:)"`.
    public var description: String {
        let fileName = fileID.split(separator: "/").last.map(String.init) ?? fileID
        return "\(fileName) · \(function)"
    }
}

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
    public let tags: [LogTag]

    /// Data attached at the call site (see `LogAttachment`).
    public let attachments: [LogAttachment]

    /// The function and file that emitted this record; `nil` for
    /// system-synthesized records (drop reports, orphan closes, expiry).
    public let callSite: LogCallSite?

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
        tags: [LogTag] = [],
        attachments: [LogAttachment] = [],
        callSite: LogCallSite? = nil,
    ) {
        self.id = id
        self.date = date
        self.event = event
        self.scopes = scopes
        self.tags = tags
        self.attachments = attachments
        self.callSite = callSite
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

    /// Whether the overflow drop policy must keep this record — the
    /// event type's ``LogEvent/isProtectedFromDropping`` opt-in. Span
    /// began/ended events set it so pairs never split under drop
    /// pressure: a dropped began strands its end, and a dropped end
    /// reads as still-open until the next launch's orphan sweep.
    /// (`SpanOverdue` stays droppable — a disposable warning.)
    var isProtectedFromDropping: Bool {
        type(of: event).isProtectedFromDropping
    }
}
