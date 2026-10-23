import PeriscopeCore

@LogScope("Elsewhere")
enum ElsewhereModelLog {
    @LogEvent("load-failed", level: .warning)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load Elsewhere: \(error.description)"
        }
    }
}
