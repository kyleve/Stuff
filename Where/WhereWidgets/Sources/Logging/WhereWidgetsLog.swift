import PeriscopeCore

@LogScope("WhereWidgets")
enum WhereWidgetsLog {
    @LogEvent(
        "no-published-snapshot",
        level: .warning,
        message: "No published widget snapshot; rendering empty state",
    )
    struct NoPublishedSnapshot {}

    @LogEvent("app-group-unavailable", level: .error)
    struct AppGroupUnavailable {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Widget App Group unavailable: \(description)"
        }
    }
}
