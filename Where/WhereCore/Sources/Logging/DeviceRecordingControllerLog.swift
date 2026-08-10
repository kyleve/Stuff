import PeriscopeCore

/// Structured failures from local recording and synced-removal reconciliation.
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
                "Failed to reconcile recording state; recording was stopped: \(description)"
            case let .rollbackRecoveryFailed(description):
                "Failed to restore recording after an operation rolled back: \(description)"
            case let .importRecoveryFailed(description):
                "Backup committed, but recording could not be restored and was stopped: \(description)"
        }
    }
}
