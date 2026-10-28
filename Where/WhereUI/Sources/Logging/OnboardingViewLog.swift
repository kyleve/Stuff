import PeriscopeCore

/// Structured events for `OnboardingView`.
@LogScope("Onboarding")
enum OnboardingViewLog {
    @LogEvent("region-commit-failed", level: .warning, version: 2)
    struct RegionCommitFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to commit onboarding region picks: \(error.description)"
        }
    }

    @LogEvent("backup-restore-failed", level: .warning, version: 2)
    struct BackupRestoreFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Onboarding backup restore failed: \(error.description)"
        }
    }

    @LogEvent("backup-restore-cleanup-failed", level: .error, version: 2)
    struct BackupRestoreCleanupFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Onboarding backup restore committed but recording cleanup failed: \(error.description)"
        }
    }

    @LogEvent(
        "location-permission-denied",
        level: .info,
        message: "Location access declined during onboarding",
    )
    struct LocationPermissionDenied {}

    @LogEvent("installation-context-write-failed", level: .error, version: 2)
    struct InstallationContextWriteFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to persist the installation recording context: \(error.description)"
        }
    }

    @LogEvent("installation-context-security-cleanup-failed", level: .error, version: 2)
    struct InstallationContextSecurityCleanupFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var exclusionError: LogError
        @LogField(exposure: .restricted, kind: .errorDetails)
        var cleanupError: LogError
        var message: String {
            "Failed to exclude the installation recording context from backup "
                + "(\(exclusionError.description)) and failed to remove it safely (\(cleanupError.description))"
        }
    }

    @LogEvent(
        "discarded-corrupt-installation-context-pending",
        level: .warning,
        message: "Discarded a corrupt pending installation recording context",
    )
    struct DiscardedCorruptInstallationContextPending {}

    @LogEvent("scope-creation-failed", level: .error, version: 2)
    struct ScopeCreationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to open the store during onboarding: \(error.description)"
        }
    }

    @LogEvent("recording-configuration-failed", level: .error, version: 2)
    struct RecordingConfigurationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to apply the onboarding recording choice: \(error.description)"
        }
    }

    @LogEvent("demo-build-failed", level: .warning, version: 2)
    struct DemoBuildFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to build the demo world: \(error.description)"
        }
    }
}
