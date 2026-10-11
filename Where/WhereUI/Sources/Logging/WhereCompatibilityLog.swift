import PeriscopeCore

@LogScope("WhereCompatibility")
enum WhereCompatibilityLog {
    @LogEvent("verification-failed", level: .warning, message: "Compatibility bootstrap failed.")
    struct VerificationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
    }
}
