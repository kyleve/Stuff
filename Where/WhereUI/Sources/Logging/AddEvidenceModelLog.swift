import PeriscopeCore
import WhereCore

/// Structured events for `AddEvidenceModel`, the compose form.
@LogScope("AddEvidenceModel")
enum AddEvidenceModelLog {
    @LogEvent("attachment-pick-failed", level: .warning)
    struct AttachmentPickFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Evidence attachment pick failed: \(description)"
        }
    }

    @LogEvent("saved", level: .info)
    struct Saved {
        @LogField("evidence_id", exposure: .restricted, kind: .identifier)
        var evidenceID: String

        var message: String {
            "Saved evidence \(evidenceID) from compose form"
        }

        var externalID: String? {
            WhereStoreID.evidence(evidenceID)
        }
    }

    @LogEvent("save-failed", level: .warning)
    struct SaveFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to save evidence: \(description)"
        }
    }
}
