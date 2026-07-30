import PeriscopeCore

/// Structured events for `DataIssueAlertReconciler`.
enum DataIssueAlertReconcilerLog: LogEvent {
    /// Names the reconciler's timed span.
    enum SpanName: Hashable {
        /// One alert reconcile: the unresolved-issue count (a scan, unless the
        /// scanner's cache is warm) and the scheduler round-trip.
        case reconcile
    }

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
