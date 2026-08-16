import PeriscopeCore

/// Structured failures for the advisory recording-configuration warning.
@LogScope("RecordingConfigurationWarning")
enum RecordingConfigurationWarningModelLog {
    @LogEvent("authority-load-failed", level: .warning)
    struct AuthorityLoadFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to resolve primary recording-device authority: \(description)"
        }
    }
}
