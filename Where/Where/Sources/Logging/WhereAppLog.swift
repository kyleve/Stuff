import PeriscopeCore

/// Process-level events from the Where application host.
@LogScope("WhereApp")
enum WhereAppLog {
    @LogEvent(
        "diagnostic-provider-startup-failed",
        level: .error,
        message: "The diagnostic reporting provider did not start.",
    )
    struct DiagnosticProviderStartupFailed {}
}
