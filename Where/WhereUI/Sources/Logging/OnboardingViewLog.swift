import PeriscopeCore

/// Structured events for `OnboardingView`. Most are degraded-but-handled — the
/// flow continues and the user isn't stranded — so they log at `.warning`;
/// only a scope that can't be created is fatal to the launch.
enum OnboardingViewLog: LogEvent {
    case regionCommitFailed(description: String)
    case backupRestoreFailed(description: String)
    case backupRestoreCleanupFailed(description: String)
    /// The user declined (or is restricted from) location access at the
    /// onboarding ask. Expected, not a failure: tracking stays
    /// intended-but-inactive and Settings offers the route to grant it.
    case locationPermissionDenied
    /// The non-backed-up installation sidecar could not be persisted, so the
    /// app cannot safely register a stable recording identity.
    case installationContextWriteFailed(description: String)
    /// Backup exclusion failed and the unsafe sidecar could not be removed either.
    case installationContextSecurityCleanupFailed(
        exclusionDescription: String,
        cleanupDescription: String,
    )
    /// A crash left an atomically written replacement that could not decode; the older
    /// authoritative context remains usable and the corrupt pending copy was removed.
    case discardedCorruptInstallationContextPending
    /// Opening the user's store failed, so onboarding can't hand the launch a
    /// world to run in. Fails the gate, landing on the failure surface.
    case scopeCreationFailed(description: String)
    /// The stable device registration or selected recording command could not be persisted.
    case recordingConfigurationFailed(description: String)
    /// Building the demo world failed. Recoverable: the intro comes back with
    /// an alert, and every other way forward still works.
    case demoBuildFailed(description: String)

    static let eventName = "Onboarding"

    var level: LogLevel {
        switch self {
            case .regionCommitFailed, .backupRestoreFailed, .demoBuildFailed,
                 .discardedCorruptInstallationContextPending: .warning
            case .locationPermissionDenied: .info
            case .installationContextWriteFailed, .installationContextSecurityCleanupFailed,
                 .scopeCreationFailed,
                 .recordingConfigurationFailed, .backupRestoreCleanupFailed: .error
        }
    }

    var message: String {
        switch self {
            case let .regionCommitFailed(description):
                "Failed to commit onboarding region picks: \(description)"
            case let .backupRestoreFailed(description):
                "Onboarding backup restore failed: \(description)"
            case let .backupRestoreCleanupFailed(description):
                "Onboarding backup restore committed but recording cleanup failed: \(description)"
            case .locationPermissionDenied:
                "Location access declined during onboarding"
            case let .installationContextWriteFailed(description):
                "Failed to persist the installation recording context: \(description)"
            case let .installationContextSecurityCleanupFailed(exclusion, cleanup):
                "Failed to exclude the installation recording context from backup "
                    + "(\(exclusion)) and failed to remove it safely (\(cleanup))"
            case .discardedCorruptInstallationContextPending:
                "Discarded a corrupt pending installation recording context"
            case let .scopeCreationFailed(description):
                "Failed to open the store during onboarding: \(description)"
            case let .recordingConfigurationFailed(description):
                "Failed to apply the onboarding recording choice: \(description)"
            case let .demoBuildFailed(description):
                "Failed to build the demo world: \(description)"
        }
    }
}
