import PeriscopeCore

/// Structured events for `OnboardingView`. Neither failure should strand the
/// user in onboarding — each is logged and the flow continues — so both log at
/// `.warning`.
enum OnboardingViewLog: LogEvent {
    case regionCommitFailed(description: String)
    case backupRestoreFailed(description: String)

    static let eventName = "Onboarding"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .regionCommitFailed(description):
                "Failed to commit onboarding region picks: \(description)"
            case let .backupRestoreFailed(description):
                "Onboarding backup restore failed: \(description)"
        }
    }
}
