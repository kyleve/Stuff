import PeriscopeCore
import WhereCore

@LogScope("EvidenceListModel")
enum EvidenceListModelLog {
    @LogEvent("load-failed", level: .warning)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int

        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to load evidence for \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }
}
