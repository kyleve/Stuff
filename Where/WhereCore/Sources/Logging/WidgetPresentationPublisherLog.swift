import PeriscopeCore

/// Structured events for publishing the widget presentation theme.
enum WidgetPresentationPublisherLog: LogEvent {
    case published(theme: String)
    case publishFailed(description: String)

    static let eventName = "WidgetPresentationPublisher"

    var level: LogLevel {
        switch self {
            case .published: .info
            case .publishFailed: .error
        }
    }

    var message: String {
        switch self {
            case let .published(theme):
                "Published widget presentation theme \(theme)"
            case let .publishFailed(description):
                "Failed to publish widget presentation: \(description)"
        }
    }
}
