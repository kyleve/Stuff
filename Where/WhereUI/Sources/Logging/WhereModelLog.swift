import PeriscopeCore

/// Structured events for `WhereModel`.
@LogScope("WhereModel")
enum WhereModelLog {
    @LogEvent("onboarding-completed", message: "Onboarding completed")
    struct OnboardingCompleted {}

    @LogEvent("opened-real-scope", message: "Opened the real scope")
    struct OpenedRealScope {}

    @LogEvent("started-session")
    struct StartedSession {
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int

        var message: String {
            "Started session (year: \(year))"
        }
    }

    @LogEvent("ended-session", message: "Ended session")
    struct EndedSession {}

    @LogEvent("reset-preferences", message: "Reset preferences to first-install defaults")
    struct ResetPreferences {}

    @LogEvent("entered-demo-mode", message: "Entered demo mode")
    struct EnteredDemoMode {}

    @LogEvent("exited-demo-mode", message: "Exited demo mode")
    struct ExitedDemoMode {}
}
