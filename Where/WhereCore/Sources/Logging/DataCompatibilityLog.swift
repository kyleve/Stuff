import PeriscopeCore

/// Failures at the shared-data boundary, without device names or user data.
enum DataCompatibilityLog: LogEvent {
    case accessBlocked(description: String)
    case subscriptionFailed(description: String)

    static let eventName = "DataCompatibility"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .subscriptionFailed(description): "Recording authority push subscription failed: \(description)"
            case let .accessBlocked(description): "Shared data access is blocked: \(description)"
        }
    }
}
