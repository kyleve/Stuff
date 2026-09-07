import PeriscopeCore

@LogScope("WidgetRefresher")
enum WidgetTimelineRefresherLog {
    @LogEvent("wrote-snapshot", message: "Wrote widget snapshot to App Group; reloading timelines")
    struct WroteSnapshot {}

    @LogEvent("publish-failed", level: .error)
    struct PublishFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to publish widget snapshot: \(description)"
        }
    }
}
