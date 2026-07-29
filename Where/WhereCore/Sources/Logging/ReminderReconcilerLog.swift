import PeriscopeCore

/// Structured events for `ReminderReconciler`. Failing to reconcile the schedule
/// is an outright failure (`.error`); failing only the badge scan is
/// degraded-but-handled (`.warning`).
enum ReminderReconcilerLog: LogEvent {
    /// Names the reconciler's timed span.
    enum SpanName: Hashable {
        /// One badge + schedule reconcile: the year report, the issue scan
        /// folded into the badge, and the scheduler round-trip. `reconcile()` is
        /// the app's most-run derived-state refresh (every launch, foreground,
        /// write, and settings change), so its span is the honest measure of
        /// "what a write costs after it commits".
        case reconcile
    }

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
