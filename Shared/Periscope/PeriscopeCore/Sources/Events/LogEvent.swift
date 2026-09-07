import Foundation

/// A structured, strongly typed log event.
///
/// Conforming types are plain `Codable` values — their stored properties are
/// the structured payload that Periscope persists and the tooling can decode
/// and display. Each event also renders a human-readable `message` line and
/// carries a `level`.
///
/// ```swift
/// struct PhotoUploaded: LogEvent {
///     var photoID: String
///     var byteCount: Int
///     var message: String { "Uploaded photo \(photoID) (\(byteCount) bytes)" }
/// }
/// ```
///
/// Events are emitted through a typed logger: `Log<PhotoUploaded>` can log
/// only `PhotoUploaded` values (plus freeform ``Message`` conveniences).
public protocol LogEvent: Codable, Sendable {
    /// The token type naming this event's spans — `log.measure(.saveEvent)`
    /// resolves against it. Defaults to `String` for freeform span names;
    /// declare a nested enum for typed tokens:
    ///
    /// ```swift
    /// struct DatabaseLogs: LogEvent {
    ///     enum SpanName: Hashable, Sendable { case saveEvent, migration }
    ///     // ...
    /// }
    /// ```
    associatedtype SpanName: Hashable, Sendable = String

    /// Stable name the event persists under; defaults to the type name.
    ///
    /// Persisted payloads are keyed by this name (plus ``eventVersion``), so
    /// renaming a type without overriding `eventName` orphans its history.
    static var eventName: String { get }

    /// Version of the payload shape, persisted alongside ``eventName`` so
    /// old rows remain identifiable after a type changes shape. Defaults
    /// to 1; bump when changing stored properties incompatibly.
    static var eventVersion: Int { get }

    /// Severity of this event. Defaults to ``LogLevel/info``.
    var level: LogLevel { get }

    /// Human-readable rendering, shown in Console.app and the log viewer.
    var message: String { get }

    /// A deliberately PII-free rendering for approved remote export. The safe
    /// default is the stable event name; events may opt into richer static copy.
    var remoteMessage: String { get }

    /// An identifier linking this event to the object it's about — a
    /// photo's URI in the local store, a Core Data managed object ID's
    /// URI representation — so tooling can find every event about an
    /// object (`LogQuery.externalID`) or look the object up from an
    /// event. Defaults to `nil`; the format is the app's to choose.
    var externalID: String? { get }

    /// Operational fields this event explicitly approves for redacted remote
    /// export. Arbitrary payload properties are never inferred or copied.
    var remoteFields: [RemoteLogField] { get }

    /// Whether the overflow drop policy must keep records of this event
    /// under queue pressure (see
    /// ``Periscope/Configuration/pendingBufferCapacity``). Defaults to
    /// `false`; span began/ended events opt in so pairs never split.
    /// Reserve for events whose *absence* corrupts the story the log
    /// tells — protected records can push the queue past its bound.
    static var isProtectedFromDropping: Bool { get }
}

extension LogEvent {
    public static var eventName: String {
        String(describing: Self.self)
    }

    public static var eventVersion: Int {
        1
    }

    public var level: LogLevel {
        .info
    }

    public static var isProtectedFromDropping: Bool {
        false
    }

    public var externalID: String? {
        nil
    }

    public var remoteMessage: String {
        Self.eventName
    }

    public var remoteFields: [RemoteLogField] {
        []
    }
}
