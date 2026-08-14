import PeriscopeCore

/// Structured failures from local recording and synced-removal reconciliation.
@LogScope("DeviceRecordingController")
enum DeviceRecordingControllerLog {
    @LogEvent("policy-observation-failed", level: .error)
    struct PolicyObservationFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to reconcile recording state; recording was stopped: \(description)"
        }
    }

    @LogEvent("rollback-recovery-failed", level: .error)
    struct RollbackRecoveryFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to restore recording after an operation rolled back: \(description)"
        }
    }

    @LogEvent("import-recovery-failed", level: .error)
    struct ImportRecoveryFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Backup committed, but recording could not be restored and was stopped: \(description)"
        }
    }
}
