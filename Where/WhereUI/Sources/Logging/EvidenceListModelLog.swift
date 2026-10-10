import PeriscopeCore
import WhereCore

@LogScope("EvidenceListModel")
enum EvidenceListModelLog {
    @LogEvent("load-failed", level: .warning, version: 2)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int

        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to load evidence for \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }
}
