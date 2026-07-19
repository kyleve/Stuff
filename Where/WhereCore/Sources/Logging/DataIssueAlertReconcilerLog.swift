import PeriscopeCore

/// Structured events for `DataIssueAlertReconciler`.
enum DataIssueAlertReconcilerLog: LogEvent {
    case reconcileFailed(description: String)

    static let eventName = "DataIssueAlertReconciler"

    var level: LogLevel {
        .error
    }

    var message: String {
        switch self {
            case let .reconcileFailed(description):
                "Failed to reconcile issue alerts: \(description)"
        }
    }
}
