import PeriscopeCore

/// Structured events for `FileLocationOutbox`.
@LogScope("LocationOutbox")
enum LocationOutboxLog {
    @LogEvent(
        "no-application-support",
        level: .warning,
        message: "No Application Support directory; using in-memory retry queue (backlog won't survive relaunch)",
    )
    struct NoApplicationSupport {}

    @LogEvent("dropped-unreadable-backlog", level: .error, version: 2)
    struct DroppedUnreadableBacklog {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Dropping unreadable location retry backlog: \(error.description)"
        }
    }

    @LogEvent("read-backlog-failed", level: .error, version: 2)
    struct ReadBacklogFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to read location retry backlog; preserving it for retry: \(error.description)"
        }
    }

    @LogEvent(
        "recovered-torn-journal",
        level: .warning,
        message: "Recovered the last intact location retry snapshot after a torn journal entry",
    )
    struct RecoveredTornJournal {}

    @LogEvent("persist-backlog-failed", level: .error, version: 2)
    struct PersistBacklogFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to persist location retry backlog: \(error.description)"
        }
    }

    @LogEvent("exclude-from-backup-failed", level: .error, version: 2)
    struct ExcludeFromBackupFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to exclude location retry backlog from device backup: \(error.description)"
        }
    }

    @LogEvent("discard-insecure-backlog-failed", level: .error, version: 2)
    struct DiscardInsecureBacklogFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to discard a backup-eligible location retry backlog: \(error.description)"
        }
    }
}
