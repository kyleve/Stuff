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

    @LogEvent("dropped-unreadable-backlog", level: .error)
    struct DroppedUnreadableBacklog {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Dropping unreadable location retry backlog: \(description)"
        }
    }

    @LogEvent("read-backlog-failed", level: .error)
    struct ReadBacklogFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to read location retry backlog; preserving it for retry: \(description)"
        }
    }

    @LogEvent(
        "recovered-torn-journal",
        level: .warning,
        message: "Recovered the last intact location retry snapshot after a torn journal entry",
    )
    struct RecoveredTornJournal {}

    @LogEvent("persist-backlog-failed", level: .error)
    struct PersistBacklogFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to persist location retry backlog: \(description)"
        }
    }

    @LogEvent("exclude-from-backup-failed", level: .error)
    struct ExcludeFromBackupFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to exclude location retry backlog from device backup: \(description)"
        }
    }

    @LogEvent("discard-insecure-backlog-failed", level: .error)
    struct DiscardInsecureBacklogFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to discard a backup-eligible location retry backlog: \(description)"
        }
    }
}
