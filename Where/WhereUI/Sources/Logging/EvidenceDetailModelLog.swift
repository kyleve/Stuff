import PeriscopeCore
import WhereCore

/// Structured events for `EvidenceDetailModel`. The evidence id rides on
/// `externalID` so blob-load failures trace to their row.
enum EvidenceDetailModelLog: LogEvent {
    case blobLoadFailed(evidenceID: String, description: String)

    static let eventName = "EvidenceDetailModel"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .blobLoadFailed(evidenceID, description):
                "Failed to load evidence blob for \(evidenceID): \(description)"
        }
    }

    var externalID: String? {
        switch self {
            case let .blobLoadFailed(evidenceID, _): WhereStoreID.evidence(evidenceID)
        }
    }
}
