import PeriscopeCore
import WhereCore

@LogScope("EvidenceDetailModel")
enum EvidenceDetailModelLog {
    @LogEvent("blob-load-failed", level: .warning)
    struct BlobLoadFailed {
        @LogField("evidence_id", exposure: .restricted, kind: .identifier)
        var evidenceID: String

        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to load evidence blob for \(evidenceID): \(description)"
        }

        var externalID: String? {
            WhereStoreID.evidence(evidenceID)
        }
    }
}
