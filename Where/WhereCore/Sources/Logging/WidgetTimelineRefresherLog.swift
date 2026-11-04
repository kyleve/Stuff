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

    @LogEvent("publish-failed", level: .error, version: 2)
    struct PublishFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to publish widget snapshot: \(error.description)"
        }
    }
}
