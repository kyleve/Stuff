import PeriscopeCore

/// Structured events for `WhereModel`, the app's top-level session/onboarding
/// coordinator. All are successful-lifecycle `.info` events.
enum WhereModelLog: LogEvent {
    private enum RemoteKind: String, CaseIterable {
        case onboardingCompleted = "onboarding-completed"
        case openedRealScope = "opened-real-scope"
        case startedSession = "started-session"
        case endedSession = "ended-session"
        case resetPreferences = "reset-preferences"
        case enteredDemoMode = "entered-demo-mode"
        case exitedDemoMode = "exited-demo-mode"
    }

    case onboardingCompleted
    /// The user's real scope was built — the app's one on-disk store open.
    /// Fires when they first commit to using the app for real, not at launch.
    case openedRealScope
    case startedSession(year: Int)
    case endedSession
    case resetPreferences
    /// Logged in to a demo world. Everything from here until
    /// ``exitedDemoMode`` describes fabricated data in memory, so a log read
    /// back later isn't mistaken for the user's real history.
    case enteredDemoMode
    case exitedDemoMode

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
            case .enteredDemoMode:
                "Entered demo mode"
            case .exitedDemoMode:
                "Exited demo mode"
        }
    }

    var remoteFields: [RemoteLogField] {
        [RemoteLogField.eventKind(remoteKind)]
    }

    private var remoteKind: RemoteKind {
        switch self {
            case .onboardingCompleted: .onboardingCompleted
            case .openedRealScope: .openedRealScope
            case .startedSession: .startedSession
            case .endedSession: .endedSession
            case .resetPreferences: .resetPreferences
            case .enteredDemoMode: .enteredDemoMode
            case .exitedDemoMode: .exitedDemoMode
        }
    }
}
