import PeriscopeCore

/// Structured failures from local recording and synced-removal reconciliation.
@LogScope("DeviceRecordingController")
enum DeviceRecordingControllerLog {
    @LogEvent("policy-observation-failed", level: .error, version: 2)
    struct PolicyObservationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to reconcile recording state; recording was stopped: \(error.description)"
        }
    }

    @LogEvent("rollback-recovery-failed", level: .error, version: 2)
    struct RollbackRecoveryFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to restore recording after an operation rolled back: \(error.description)"
        }
    }

    @LogEvent("import-recovery-failed", level: .error, version: 2)
    struct ImportRecoveryFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Backup committed, but recording could not be restored and was stopped: \(error.description)"
        }
    }
}
