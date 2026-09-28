import PeriscopeCore

@LogScope("Resolve")
enum ResolveModelLog {
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
