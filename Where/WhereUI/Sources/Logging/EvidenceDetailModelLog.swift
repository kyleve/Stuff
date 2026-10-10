import PeriscopeCore
import WhereCore

@LogScope("EvidenceDetailModel")
enum EvidenceDetailModelLog {
    @LogEvent("blob-load-failed", level: .warning, version: 2)
    struct BlobLoadFailed {
        @LogField(exposure: .restricted, kind: .identifier)
        var evidenceID: String

        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to load evidence blob for \(evidenceID): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.evidence(evidenceID)
        }
    }
}
