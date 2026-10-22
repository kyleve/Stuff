import PeriscopeCore

/// Offline use preserves verified authority without hiding the failed refresh.
@LogScope("RecordingCoordination")
enum RecordingCoordinationLog {
    @LogEvent(
        "using-cached-authority",
        level: .warning,
        message: "Authority refresh is unavailable; using the last verified state.",
    )
    struct UsingCachedAuthority {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
    }
}
