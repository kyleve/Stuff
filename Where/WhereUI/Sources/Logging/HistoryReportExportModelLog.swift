import PeriscopeCore

@LogScope("HistoryReportExport")
enum HistoryReportExportModelLog {
    @LogEvent("operation-failed", level: .warning)
    struct OperationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "History report export failed: \(error.description)"
        }
    }
}
