import PeriscopeCore

@LogScope("WhereWidgets")
enum WhereWidgetsLog {
    @LogEvent(
        "no-published-snapshot",
        level: .warning,
        message: "No published widget snapshot; rendering empty state",
    )
    struct NoPublishedSnapshot {}

    @LogEvent("compatibility-blocked", level: .warning)
    struct CompatibilityBlocked {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Widget data access blocked: \(error.description)"
        }
    }
}
