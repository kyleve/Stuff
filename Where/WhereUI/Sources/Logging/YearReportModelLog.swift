import PeriscopeCore
import WhereCore

/// Structured events for `YearReportModel`. The affected year rides on
/// `externalID`. A successful load is `.info`; read failures that leave a
/// degraded UI state are `.warning`.
enum YearReportModelLog: LogEvent {
    case selectedYear(year: Int)
    case reportLoaded(year: Int, dayCount: Int)
    case reportLoadFailed(year: Int, description: String)
    case evidenceDayKeysLoadFailed(year: Int, description: String)
    case dataIssueScanFailed(description: String)
    case clearYearFailed(year: Int, description: String)
    case locationsLoadFailed(region: String, year: Int, description: String)
    case dayLocationsLoadFailed(day: String, year: Int, description: String)
    case representativeCoordinatesLoadFailed(year: Int, description: String)

    static let eventName = "YearReport"

    var level: LogLevel {
        switch self {
            case .selectedYear, .reportLoaded: .info
            case .reportLoadFailed, .evidenceDayKeysLoadFailed, .dataIssueScanFailed,
                 .clearYearFailed, .locationsLoadFailed, .dayLocationsLoadFailed,
                 .representativeCoordinatesLoadFailed:
                .warning
        }
    }

    var message: String {
        switch self {
            case let .selectedYear(year):
                "Selected year \(year)"
            case let .reportLoaded(year, dayCount):
                "Year report loaded for \(year) (\(dayCount) day(s))"
            case let .reportLoadFailed(year, description):
                "Failed to load year report for \(year): \(description)"
            case let .evidenceDayKeysLoadFailed(year, description):
                "Failed to load evidence day keys for \(year): \(description)"
            case let .dataIssueScanFailed(description):
                "Failed to scan for data issues: \(description)"
            case let .clearYearFailed(year, description):
                "Failed to clear year \(year): \(description)"
            case let .locationsLoadFailed(region, year, description):
                "Failed to load locations for \(region) in \(year): \(description)"
            case let .dayLocationsLoadFailed(day, year, description):
                "Failed to load locations for day \(day) in \(year): \(description)"
            case let .representativeCoordinatesLoadFailed(year, description):
                "Failed to load representative coordinates for \(year): \(description)"
        }
    }

    var externalID: String? {
        switch self {
            case let .selectedYear(year), let .reportLoaded(year, _),
                 let .reportLoadFailed(year, _), let .evidenceDayKeysLoadFailed(year, _),
                 let .clearYearFailed(year, _), let .locationsLoadFailed(_, year, _),
                 let .representativeCoordinatesLoadFailed(year, _):
                WhereStoreID.year(year)
            case let .dayLocationsLoadFailed(day, _, _):
                WhereStoreID.day(day)
            case .dataIssueScanFailed:
                nil
        }
    }
}
