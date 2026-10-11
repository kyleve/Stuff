import PeriscopeCore

enum WhereCompatibilityLog: LogEvent {
    case verificationFailed(description: String)
    static let eventName = "WhereCompatibility"
    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .verificationFailed(description): "Compatibility bootstrap failed: \(description)"
        }
    }
}
