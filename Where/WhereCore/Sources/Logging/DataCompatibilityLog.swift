import PeriscopeCore

/// Failures at the shared-data boundary, without device names or user data.
enum DataCompatibilityLog: LogEvent {
    case accessBlocked(description: String)

    static let eventName = "DataCompatibility"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .accessBlocked(description): "Shared data access is blocked: \(description)"
        }
    }
}
