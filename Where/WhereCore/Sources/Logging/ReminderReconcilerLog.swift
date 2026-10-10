import PeriscopeCore

/// Structured events for `ReminderReconciler`.
@LogScope("ReminderReconciler")
enum ReminderReconcilerLog {
    enum SpanName: Hashable {
        case reconcile
    }

    @LogEvent("reconcile-failed", level: .error, version: 2)
    struct ReconcileFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to reconcile logging reminders: \(error.description)"
        }
    }

    @LogEvent("badge-scan-failed", level: .warning, version: 2)
    struct BadgeScanFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to scan data issues for badge: \(error.description)"
        }
    }
}
