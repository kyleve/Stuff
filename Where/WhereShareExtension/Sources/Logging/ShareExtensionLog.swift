import PeriscopeCore

/// Structured events for the Where share extension — a short-lived, separate
/// process, so `Periscope.shared` stays OSLog-only (no persistent store).
enum ShareExtensionLog: LogEvent {
    /// Names the extension's timed span. The save path isn't here: opening the
    /// App Group store and committing the write are both spanned by
    /// `SwiftDataStore` itself.
    enum SpanName: Hashable {
        /// Pulling the bytes out of every shared item provider — the wait between
        /// tapping Share and the compose form appearing, and the only part of the
        /// extension's work that scales with what the user shared (a multi-page
        /// PDF, twenty photos).
        case loadAttachments
    }

    /// The extension was invoked with the given number of shared items.
    case opened(itemCount: Int)
    /// A shared item provider yielded no bytes for its offered type. `reason` is
    /// the error it reported, absent when it simply handed back nothing.
    case attachmentLoadFailed(typeIdentifier: String, reason: String?)
    /// A shared URL provider produced nothing readable.
    case urlUnreadable(reason: String?)
    /// Shared evidence records were persisted to the App Group store.
    case saved(evidenceCount: Int)
    /// Persisting the shared evidence failed; the form stays open.
    case saveFailed(description: String)

    static let eventName = "ShareExtension"

    var level: LogLevel {
        switch self {
            case .opened, .saved:
                .info
            case .attachmentLoadFailed, .urlUnreadable:
                .warning
            case .saveFailed:
                .error
        }
    }

    var message: String {
        switch self {
            case let .opened(itemCount):
                "Share extension opened with \(itemCount) item(s)"
            case let .attachmentLoadFailed(typeIdentifier, reason):
                "Failed to load shared \(typeIdentifier): \(reason ?? "provider returned nothing")"
            case let .urlUnreadable(reason):
                "Shared URL provider yielded no readable URL:"
                    + " \(reason ?? "provider returned nothing")"
            case let .saved(evidenceCount):
                "Saved \(evidenceCount) shared evidence record(s)"
            case let .saveFailed(description):
                "Failed to save shared evidence: \(description)"
        }
    }
}
