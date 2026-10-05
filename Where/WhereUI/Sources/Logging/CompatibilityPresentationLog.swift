import PeriscopeCore

enum CompatibilityPresentationLog: LogEvent {
    case accessBlocked(description: String)
    static let eventName = "CompatibilityPresentation"
    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .accessBlocked(description): "Compatibility verification failed: \(description)"
        }
    }
}
