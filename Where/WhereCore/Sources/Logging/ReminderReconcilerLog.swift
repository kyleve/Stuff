import PeriscopeCore

/// Structured events for `ReminderReconciler`. Failing to reconcile the schedule
/// is an outright failure (`.error`); failing only the badge scan is
/// degraded-but-handled (`.warning`).
enum ReminderReconcilerLog: LogEvent {
    case reconcileFailed(description: String)
    case badgeScanFailed(description: String)

    static let eventName = "ReminderReconciler"

    var level: LogLevel {
        switch self {
            case .reconcileFailed: .error
            case .badgeScanFailed: .warning
        }
    }

    var message: String {
        switch self {
            case let .reconcileFailed(description):
                "Failed to reconcile logging reminders: \(description)"
            case let .badgeScanFailed(description):
                "Failed to scan data issues for badge: \(description)"
        }
    }
}
