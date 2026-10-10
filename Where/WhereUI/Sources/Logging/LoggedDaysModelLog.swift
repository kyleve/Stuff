import PeriscopeCore
import WhereCore

@LogScope("LoggedDaysModel")
enum LoggedDaysModelLog {
    @LogEvent("load-failed", level: .warning)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int

        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to load logged days for \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }
}
