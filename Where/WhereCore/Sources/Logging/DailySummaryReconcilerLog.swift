import PeriscopeCore

/// Structured events for `DailySummaryReconciler`.
enum DailySummaryReconcilerLog: LogEvent {
    /// Names the reconciler's timed span.
    enum SpanName: Hashable {
        /// One recap reconcile: the year report, the ranked body, and the
        /// scheduler round-trip.
        case reconcile
    }

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
