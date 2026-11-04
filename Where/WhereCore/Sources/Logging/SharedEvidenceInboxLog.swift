import PeriscopeCore

/// Diagnostics for durable share drafts, which remain outside the history store until admitted.
@LogScope("SharedEvidenceInbox")
enum SharedEvidenceInboxLog {
    enum SpanName: Hashable { case importDrafts }

    @LogEvent("staging-cleanup-failed", level: .warning)
    struct StagingCleanupFailed {
        @LogField(exposure: .restricted, kind: .errorDetails) var error: LogError
        var message: String {
            "Shared evidence staging cleanup failed: \(error.description)"
        }
    }
}
