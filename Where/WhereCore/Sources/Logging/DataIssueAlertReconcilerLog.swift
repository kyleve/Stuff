import PeriscopeCore

@LogScope("DataIssueAlertReconciler")
enum DataIssueAlertReconcilerLog {
    enum SpanName: Hashable { case reconcile }

    @LogEvent("reconcile-failed", level: .error)
    struct ReconcileFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to reconcile issue alerts: \(description)"
        }
    }
}
