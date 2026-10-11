import PeriscopeCore

/// Failures at the shared-data boundary, without device names or user data.
@LogScope("DataCompatibility")
enum DataCompatibilityLog {
    @LogEvent("access-blocked", level: .warning, message: "Shared data access is blocked.")
    struct AccessBlocked {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
    }
}
