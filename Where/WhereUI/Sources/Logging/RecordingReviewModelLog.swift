import PeriscopeCore

@LogScope("RecordingReview")
enum RecordingReviewModelLog {
    @LogEvent("operation-failed", level: .warning)
    struct OperationFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Recording review operation failed: \(error.description)"
        }
    }
}
