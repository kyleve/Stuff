import PeriscopeCore
import WhereCore

@LogScope("Resolve")
enum ResolveModelLog {
    enum SpanName: String, CustomStringConvertible {
        case prepareReview
        var description: String {
            rawValue
        }
    }

    @LogEvent(
        "correction-apply-failed",
        level: .warning,
        message: "Failed to apply reviewed GPS sample corrections",
    )
    struct CorrectionApplyFailed {
        @LogField(exposure: .restricted, kind: .identifier)
        var issueID: DataIssueID
        var externalID: String? {
            issueID.storeURL.absoluteString
        }
    }

    @LogEvent("data-issue-scan-failed", level: .warning, version: 2)
    struct DataIssueScanFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to scan for data issues: \(error.description)"
        }
    }

    @LogEvent("dismiss-failed", level: .warning, version: 2)
    struct DismissFailed {
        @LogField(exposure: .restricted, kind: .identifier)
        var issueID: String

        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to dismiss data issue \(issueID): \(error.description)"
        }

        var externalID: String? {
            issueID
        }
    }
}
