import PeriscopeCore
import WhereCore

@LogScope("LoggedDaysModel")
enum LoggedDaysModelLog {
    @LogEvent("load-failed", level: .warning)
    struct LoadFailed {
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int

        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to load logged days for \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }
}
