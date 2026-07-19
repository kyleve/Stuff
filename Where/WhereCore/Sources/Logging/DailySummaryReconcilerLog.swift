import PeriscopeCore

/// Structured events for `DailySummaryReconciler`.
enum DailySummaryReconcilerLog: LogEvent {
    case reconcileFailed(description: String)

    static let eventName = "DailySummaryReconciler"

    var level: LogLevel {
        .error
    }

    var message: String {
        switch self {
            case let .reconcileFailed(description):
                "Failed to reconcile daily summary: \(description)"
        }
    }
}
