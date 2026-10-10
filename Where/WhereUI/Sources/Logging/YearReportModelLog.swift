import PeriscopeCore
import WhereCore

/// Structured events and spans for `YearReportModel`.
@LogScope("YearReport")
enum YearReportModelLog {
    enum SpanName: Hashable { case sceneRefresh }

    @LogEvent("selected-year")
    struct SelectedYear {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        var message: String {
            "Selected year \(year)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("report-loaded")
    struct ReportLoaded {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField(exposure: .shareable, kind: .count)
        var dayCount: Int
        var message: String {
            "Year report loaded for \(year) (\(dayCount) day(s))"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("report-load-failed", level: .warning, version: 2)
    struct ReportLoadFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load year report for \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("evidence-day-keys-load-failed", level: .warning, version: 2)
    struct EvidenceDayKeysLoadFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load evidence day keys for \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("data-issue-scan-failed", level: .warning, version: 2)
    struct DataIssueScanFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to scan for data issues: \(error.description)"
        }
    }

    @LogEvent("clear-year-failed", level: .warning, version: 2)
    struct ClearYearFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to clear year \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("locations-load-failed", level: .warning, version: 2)
    struct LocationsLoadFailed {
        @LogField(exposure: .restricted, kind: .location)
        var region: String
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load locations for \(region) in \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("day-locations-load-failed", level: .warning, version: 2)
    struct DayLocationsLoadFailed {
        @LogField(exposure: .restricted, kind: .dateTime)
        var day: String
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load locations for day \(day) in \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.day(day)
        }
    }

    @LogEvent("representative-coordinates-load-failed", level: .warning, version: 2)
    struct RepresentativeCoordinatesLoadFailed {
        @LogField(exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load representative coordinates for \(year): \(error.description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }
}
