import PeriscopeCore

/// Structured events for `OnboardingView`.
@LogScope("Onboarding")
enum OnboardingViewLog {
    @LogEvent("region-commit-failed", level: .warning)
    struct RegionCommitFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to commit onboarding region picks: \(description)"
        }
    }

    @LogEvent("backup-restore-failed", level: .warning)
    struct BackupRestoreFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Onboarding backup restore failed: \(description)"
        }
    }

    @LogEvent("backup-restore-cleanup-failed", level: .error)
    struct BackupRestoreCleanupFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Onboarding backup restore committed but recording cleanup failed: \(description)"
        }
    }

    @LogEvent(
        "location-permission-denied",
        level: .info,
        message: "Location access declined during onboarding",
    )
    struct LocationPermissionDenied {}

    @LogEvent("installation-context-write-failed", level: .error)
    struct InstallationContextWriteFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to persist the installation recording context: \(description)"
        }
    }

    @LogEvent("installation-context-security-cleanup-failed", level: .error)
    struct InstallationContextSecurityCleanupFailed {
        @LogField("exclusion_description", exposure: .restricted, kind: .errorDetails)
        var exclusionDescription: String
        @LogField("cleanup_description", exposure: .restricted, kind: .errorDetails)
        var cleanupDescription: String
        var message: String {
            "Failed to exclude the installation recording context from backup "
                + "(\(exclusionDescription)) and failed to remove it safely (\(cleanupDescription))"
        }
    }

    @LogEvent(
        "discarded-corrupt-installation-context-pending",
        level: .warning,
        message: "Discarded a corrupt pending installation recording context",
    )
    struct DiscardedCorruptInstallationContextPending {}

    @LogEvent("scope-creation-failed", level: .error)
    struct ScopeCreationFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to open the store during onboarding: \(description)"
        }
    }

    @LogEvent("recording-configuration-failed", level: .error)
    struct RecordingConfigurationFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to apply the onboarding recording choice: \(description)"
        }
    }

    @LogEvent("demo-build-failed", level: .warning)
    struct DemoBuildFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to build the demo world: \(description)"
        }
    }
}
