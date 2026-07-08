import Foundation

/// The built-in freeform log event: a rendered string plus a level.
///
/// `Message` is what the level convenience methods on `Log` (`log.debug(_:)`,
/// `log.error(_:)`, …) emit, so every typed logger stays freeform-capable —
/// the generic `Event` constraint applies to custom structured events only.
public struct Message: LogEvent, Hashable {
    public static let eventName = "message"

    public var level: LogLevel

    /// The stored, already-rendered message text.
    public var text: String

    public var message: String {
        text
    }

    public init(level: LogLevel, _ text: String) {
        self.level = level
        self.text = text
    }
}
