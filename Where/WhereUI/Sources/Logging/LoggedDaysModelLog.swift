import PeriscopeCore
import WhereCore

@LogScope("LoggedDaysModel")
enum LoggedDaysModelLog {
    @LogEvent("load-failed", level: .warning, version: 2)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int

        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to load logged days for \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }
}
