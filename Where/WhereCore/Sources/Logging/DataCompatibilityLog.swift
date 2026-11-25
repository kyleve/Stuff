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

    @LogEvent("invalid-change-reason", level: .warning)
    struct InvalidChangeReason {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Could not read the data model change reason: \(error.description)"
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
