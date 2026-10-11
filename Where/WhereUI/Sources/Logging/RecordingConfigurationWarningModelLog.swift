import PeriscopeCore

/// Structured failures for the advisory recording-configuration warning.
@LogScope("RecordingConfigurationWarning")
enum RecordingConfigurationWarningModelLog {
    @LogEvent("authority-load-failed", level: .warning, version: 2)
    struct AuthorityLoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to resolve primary recording-device authority: \(error.description)"
        }
    }
}
