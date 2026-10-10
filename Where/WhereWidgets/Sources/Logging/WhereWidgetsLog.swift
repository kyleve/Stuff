import PeriscopeCore

@LogScope("WhereWidgets")
enum WhereWidgetsLog {
    @LogEvent(
        "no-published-snapshot",
        level: .warning,
        message: "No published widget snapshot; rendering empty state",
    )
    struct NoPublishedSnapshot {}

    @LogEvent("app-group-unavailable", level: .error, version: 2)
    struct AppGroupUnavailable {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Widget App Group unavailable: \(error.description)"
        }
    }
}
