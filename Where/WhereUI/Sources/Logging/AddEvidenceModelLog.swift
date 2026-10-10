import PeriscopeCore
import WhereCore

/// Structured events for `AddEvidenceModel`, the compose form.
@LogScope("AddEvidenceModel")
enum AddEvidenceModelLog {
    @LogEvent("attachment-pick-failed", level: .warning, version: 2)
    struct AttachmentPickFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Evidence attachment pick failed: \(error.description)"
        }
    }

    @LogEvent("saved", level: .info)
    struct Saved {
        @LogField(exposure: .restricted, kind: .identifier)
        var evidenceID: String

        var message: String {
            "Saved evidence \(evidenceID) from compose form"
        }

        var externalID: String? {
            WhereStoreID.evidence(evidenceID)
        }
    }

    @LogEvent("save-failed", level: .warning, version: 2)
    struct SaveFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to save evidence: \(error.description)"
        }
    }
}
