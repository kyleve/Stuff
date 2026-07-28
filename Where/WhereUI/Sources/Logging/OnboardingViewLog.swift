import PeriscopeCore

/// Structured events for `OnboardingView`. Most are degraded-but-handled — the
/// flow continues and the user isn't stranded — so they log at `.warning`;
/// only a scope that can't be created is fatal to the launch.
enum OnboardingViewLog: LogEvent {
    case regionCommitFailed(description: String)
    case backupRestoreFailed(description: String)
    /// The user declined (or is restricted from) location access at the
    /// onboarding ask. Expected, not a failure: tracking stays
    /// intended-but-inactive and Settings offers the route to grant it.
    case locationPermissionDenied
    /// Opening the user's store failed, so onboarding can't hand the launch a
    /// world to run in. Fails the gate, landing on the failure surface.
    case scopeCreationFailed(description: String)
    /// Building the demo world failed. Recoverable: the intro comes back with
    /// an alert, and every other way forward still works.
    case demoBuildFailed(description: String)

    static let eventName = "Onboarding"

    var level: LogLevel {
        switch self {
            case .regionCommitFailed, .backupRestoreFailed, .demoBuildFailed: .warning
            case .locationPermissionDenied: .info
            case .scopeCreationFailed: .error
        }
    }

    var message: String {
        switch self {
            case let .regionCommitFailed(description):
                "Failed to commit onboarding region picks: \(description)"
            case let .backupRestoreFailed(description):
                "Onboarding backup restore failed: \(description)"
            case .locationPermissionDenied:
                "Location access declined during onboarding"
            case let .scopeCreationFailed(description):
                "Failed to open the store during onboarding: \(description)"
            case let .demoBuildFailed(description):
                "Failed to build the demo world: \(description)"
        }
    }
}
