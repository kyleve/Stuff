import PeriscopeCore

/// Structured events for `DailySummaryReconciler`.
@LogScope("DailySummaryReconciler")
enum DailySummaryReconcilerLog {
    enum SpanName: Hashable { case reconcile }

    @LogEvent("reconcile-failed", level: .error)
    struct ReconcileFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to reconcile daily summary: \(description)"
        }
    }
}
