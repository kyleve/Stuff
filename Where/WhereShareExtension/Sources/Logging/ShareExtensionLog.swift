import PeriscopeCore

/// Structured events for the Where share extension — a short-lived, separate
/// process, so `Periscope.shared` stays OSLog-only (no persistent store).
enum ShareExtensionLog: LogEvent {
    /// The extension was invoked with the given number of shared items.
    case opened(itemCount: Int)
    /// A shared item provider yielded no bytes for its offered type.
    case attachmentLoadFailed(typeIdentifier: String)
    /// A shared URL provider produced nothing readable.
    case urlUnreadable
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
            case let .attachmentLoadFailed(typeIdentifier):
                "Failed to load shared \(typeIdentifier)"
            case .urlUnreadable:
                "Shared URL provider yielded no readable URL"
            case let .saved(evidenceCount):
                "Saved \(evidenceCount) shared evidence record(s)"
            case let .saveFailed(description):
                "Failed to save shared evidence: \(description)"
        }
    }
}
