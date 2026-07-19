import PeriscopeCore
import WhereCore

/// Structured events for `AddEvidenceModel`, the compose form. A save records
/// the evidence id (`externalID`); attachment-pick and save failures leave the
/// form open with an honest error, so they log at `.warning`.
enum AddEvidenceModelLog: LogEvent {
    case attachmentPickFailed(description: String)
    case saved(evidenceID: String)
    case saveFailed(description: String)

    static let eventName = "AddEvidenceModel"

    var level: LogLevel {
        switch self {
            case .saved: .info
            case .attachmentPickFailed, .saveFailed: .warning
        }
    }

    var message: String {
        switch self {
            case let .attachmentPickFailed(description):
                "Evidence attachment pick failed: \(description)"
            case let .saved(evidenceID):
                "Saved evidence \(evidenceID) from compose form"
            case let .saveFailed(description):
                "Failed to save evidence: \(description)"
        }
    }

    var externalID: String? {
        switch self {
            case let .saved(evidenceID): WhereStoreID.evidence(evidenceID)
            case .attachmentPickFailed, .saveFailed: nil
        }
    }
}
