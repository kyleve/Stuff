import PeriscopeCore

/// Structured failures for the advisory recording-configuration warning.
enum RecordingConfigurationWarningModelLog: LogEvent {
    case authorityLoadFailed(description: String)

    static let eventName = "RecordingConfigurationWarning"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .authorityLoadFailed(description):
                "Failed to resolve primary recording-device authority: \(description)"
        }
    }
}
