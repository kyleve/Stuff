import PeriscopeCore
import WhereCore

/// Structured events for `LoggedDaysModel`. A read failure leaves the list in an
/// honest error state, so it logs at `.warning`. The year rides on `externalID`.
enum LoggedDaysModelLog: LogEvent {
    case loadFailed(year: Int, description: String)

    static let eventName = "LoggedDaysModel"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .loadFailed(year, description):
                "Failed to load logged days for \(year): \(description)"
        }
    }

    var externalID: String? {
        switch self {
            case let .loadFailed(year, _): WhereStoreID.year(year)
        }
    }
}
