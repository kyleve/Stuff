import PeriscopeCore

/// Structured failures from background recording-policy reconciliation.
enum DeviceRecordingControllerLog: LogEvent {
    case policyObservationFailed(description: String)
    case rollbackRecoveryFailed(description: String)
    case importRecoveryFailed(description: String)

    static let eventName = "DeviceRecordingController"

    var level: LogLevel {
        .error
    }

    var message: String {
        switch self {
            case let .policyObservationFailed(description):
                "Failed to apply a synced recording policy; recording was stopped: \(description)"
            case let .rollbackRecoveryFailed(description):
                "Failed to restore recording after an operation rolled back: \(description)"
            case let .importRecoveryFailed(description):
                "Backup committed, but recording could not be restored and was stopped: \(description)"
        }
    }
}
