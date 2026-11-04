import PeriscopeCore

@LogScope("DataCompatibility")
enum DataCompatibilityLog {
    @LogEvent("refresh-failed", level: .warning)
    struct RefreshFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Compatibility refresh failed: \(error.description)"
        }
    }
}
