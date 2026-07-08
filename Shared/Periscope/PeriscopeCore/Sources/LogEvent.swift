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
}
