import PeriscopeCore
import WhereCore

@LogScope("EvidenceDetailModel")
enum EvidenceDetailModelLog {
    @LogEvent("blob-load-failed", level: .warning)
    struct BlobLoadFailed {
        @LogField(exposure: .restricted, kind: .identifier)
        var evidenceID: String

        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to load evidence blob for \(evidenceID): \(description)"
        }

        var externalID: String? {
            WhereStoreID.evidence(evidenceID)
        }
    }
}
