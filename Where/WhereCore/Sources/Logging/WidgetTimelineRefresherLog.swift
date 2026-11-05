import PeriscopeCore

@LogScope("WidgetRefresher")
enum WidgetTimelineRefresherLog {
    @LogEvent("withdraw-failed", level: .error)
    struct WithdrawFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to withdraw widget snapshot: \(error.description)"
        }
    }

    @LogEvent("wrote-snapshot", message: "Wrote widget snapshot to App Group; reloading timelines")
    struct WroteSnapshot {}
}
