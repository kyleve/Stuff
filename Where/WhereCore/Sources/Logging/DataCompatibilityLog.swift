import PeriscopeCore

@LogScope("DataCompatibility")
enum DataCompatibilityLog {
    @LogEvent("verification-failed", level: .warning)
    struct VerificationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Data compatibility verification failed: \(error.description)"
        }
    }

    @LogEvent("blocked", level: .warning)
    struct Blocked {
        @LogField(exposure: .restricted, kind: .technicalState)
        var reason: String
        var message: String {
            "History access blocked: \(reason)"
        }
    }

    enum SpanName: String { case verify }
}
