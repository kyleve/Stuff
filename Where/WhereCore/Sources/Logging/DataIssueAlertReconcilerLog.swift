import PeriscopeCore

@LogScope("DataIssueAlertReconciler")
enum DataIssueAlertReconcilerLog {
    enum SpanName: Hashable { case reconcile }

    @LogEvent("reconcile-failed", level: .error, version: 2)
    struct ReconcileFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to reconcile issue alerts: \(error.description)"
        }
    }
}
