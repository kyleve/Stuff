import PeriscopeCore

/// Structured events for `DailySummaryReconciler`.
@LogScope("DailySummaryReconciler")
enum DailySummaryReconcilerLog {
    enum SpanName: Hashable { case reconcile }

    @LogEvent("reconcile-failed", level: .error, version: 2)
    struct ReconcileFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to reconcile daily summary: \(error.description)"
        }
    }
}
