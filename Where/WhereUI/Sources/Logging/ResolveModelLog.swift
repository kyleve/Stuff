import PeriscopeCore
import WhereCore

/// Structured events for `ResolveModel`, the data-issue resolution flow. Read /
/// dismiss failures leave an honest UI error, so they log at `.warning`. A
/// dismissed issue's id rides on `externalID`.
enum ResolveModelLog: LogEvent {
    case dataIssueScanFailed(description: String)
    case dismissFailed(issueID: String, description: String)
    case correctionApplyFailed(issueID: DataIssueID)

    static let eventName = "Resolve"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .dataIssueScanFailed(description):
                "Failed to scan for data issues: \(description)"
            case let .dismissFailed(issueID, description):
                "Failed to dismiss data issue \(issueID): \(description)"
            case .correctionApplyFailed:
                "Failed to apply reviewed GPS sample corrections"
        }
    }

    var externalID: String? {
        switch self {
            case let .dismissFailed(issueID, _): issueID
            case .dataIssueScanFailed: nil
            case let .correctionApplyFailed(issueID): issueID.storeURL.absoluteString
        }
    }
}
