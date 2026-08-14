import PeriscopeCore

/// Structured events for `ReminderReconciler`.
@LogScope("ReminderReconciler")
enum ReminderReconcilerLog {
    enum SpanName: Hashable {
        case reconcile
    }

    @LogEvent("reconcile-failed", level: .error)
    struct ReconcileFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to reconcile logging reminders: \(description)"
        }
    }

    @LogEvent("badge-scan-failed", level: .warning)
    struct BadgeScanFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to scan data issues for badge: \(description)"
        }
    }
}
