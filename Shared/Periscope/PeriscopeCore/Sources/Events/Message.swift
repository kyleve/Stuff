import Foundation

/// The built-in scope for freeform messages.
@LogScope("message")
public enum FreeformLogScope {
    /// The built-in freeform log event: a rendered string plus a level.
    ///
    /// `Message` is what the level convenience methods on `Log` (`log.debug(_:)`,
    /// `log.error(_:)`, …) emit, so every typed logger stays freeform-capable.
    @LogEvent("message")
    public struct Message: Hashable {
        @LogField(
            "level",
            exposure: .restricted,
            kind: .technicalState,
        )
        public var level: LogLevel

        /// The stored, already-rendered message text.
        @LogField(
            "text",
            exposure: .restricted,
            kind: .arbitraryText,
        )
        public var text: String

        public var message: String {
            text
        }
    }
}

public typealias Message = FreeformLogScope.Message
