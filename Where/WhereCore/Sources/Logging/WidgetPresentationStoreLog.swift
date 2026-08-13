import PeriscopeCore

/// Structured events for an unreadable widget presentation file.
enum WidgetPresentationStoreLog: LogEvent {
    case unreadablePresentation(description: String)

    static let eventName = "WidgetPresentationStore"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .unreadablePresentation(description):
                "Discarded unreadable widget presentation: \(description)"
        }
    }
}
