import PeriscopeCore
import WhereCore

@LogScope("Resolve")
enum ResolveModelLog {
    enum SpanName: String, CustomStringConvertible {
        case prepareReview
        var description: String { rawValue }
    }

    @LogEvent("correction-apply-failed", level: .warning,
        message: "Failed to apply reviewed GPS sample corrections")
    struct CorrectionApplyFailed {
        @LogField("issue_id", exposure: .restricted, kind: .identifier)
        var issueID: DataIssueID
        var externalID: String? { issueID.storeURL.absoluteString }
    }

    @LogEvent("data-issue-scan-failed", level: .warning)
    struct DataIssueScanFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to scan for data issues: \(description)"
        }
    }

    @LogEvent("dismiss-failed", level: .warning)
    struct DismissFailed {
        @LogField("issue_id", exposure: .restricted, kind: .identifier)
        var issueID: String

        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to dismiss data issue \(issueID): \(description)"
        }

        var externalID: String? {
            issueID
        }
    }
}
