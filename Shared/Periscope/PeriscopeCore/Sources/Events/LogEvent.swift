import Foundation

/// A structured, strongly typed log event.
///
/// Conforming types are plain `Codable` values — their stored properties are
/// the structured payload that Periscope persists and the tooling can decode
/// and display. Each event also renders a human-readable `message` line and
/// carries a `level`.
///
/// Repository events use ``LogEvent(_:level:message:version:)`` inside a
/// ``LogScope(_:)`` namespace. External clients can conform manually; the
/// defaults keep manual events safe by exporting no classified values.
public protocol LogEvent: Codable, Sendable {
    /// Stable name the event persists under.
    static var eventName: String { get }

    /// Version of the payload shape, persisted alongside ``eventName`` so
    /// old rows remain identifiable after a type changes shape. Defaults
    /// to 1; bump when changing stored properties incompatibly.
    static var eventVersion: Int { get }

    /// Severity of this event. Defaults to ``LogLevel/info``.
    var level: LogLevel { get }

    /// Human-readable rendering, shown in Console.app and the log viewer.
    var message: String { get }

    /// An identifier linking this event to the object it's about — a
    /// photo's URI in the local store, a Core Data managed object ID's
    /// URI representation — so tooling can find every event about an
    /// object (`LogQuery.externalID`) or look the object up from an
    /// event. Defaults to `nil`; the format is the app's to choose.
    var externalID: String? { get }

    /// The compiler-checked projection approved for remote export.
    var classifiedFields: [ClassifiedLogField] { get }

    /// Whether the overflow drop policy must keep records of this event
    /// under queue pressure (see
    /// ``Periscope/Configuration/pendingBufferCapacity``). Defaults to
    /// `false`; span began/ended events opt in so pairs never split.
    /// Reserve for events whose *absence* corrupts the story the log
    /// tells — protected records can push the queue past its bound.
    static var isProtectedFromDropping: Bool { get }
}

extension LogEvent {
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

    public var classifiedFields: [ClassifiedLogField] {
        []
    }
}
