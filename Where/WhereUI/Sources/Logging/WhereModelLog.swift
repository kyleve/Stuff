import PeriscopeCore

/// Structured events for `WhereModel`, the app's top-level session/onboarding
/// coordinator. All are successful-lifecycle `.info` events.
enum WhereModelLog: LogEvent {
    case onboardingCompleted
    /// The user's real scope was built — the app's one on-disk store open.
    /// Fires when they first commit to using the app for real, not at launch.
    case openedRealScope
    case startedSession(year: Int)
    case endedSession
    case resetPreferences

    static let eventName = "WhereModel"

    var message: String {
        switch self {
            case .onboardingCompleted:
                "Onboarding completed"
            case .openedRealScope:
                "Opened the real scope"
            case let .startedSession(year):
                "Started session (year: \(year))"
            case .endedSession:
                "Ended session"
            case .resetPreferences:
                "Reset preferences to first-install defaults"
        }
    }
}
