import PeriscopeCore
import WhereCore

/// Structured events and spans for `YearReportModel`.
@LogScope("YearReport")
enum YearReportModelLog {
    enum SpanName: Hashable { case sceneRefresh }

    @LogEvent("selected-year")
    struct SelectedYear {
        @LogField("year", exposure: .restricted, kind: .domainValue)
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
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField("day_count", exposure: .shareable, kind: .count)
        var dayCount: Int
        var message: String {
            "Year report loaded for \(year) (\(dayCount) day(s))"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("report-load-failed", level: .warning)
    struct ReportLoadFailed {
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load year report for \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("evidence-day-keys-load-failed", level: .warning)
    struct EvidenceDayKeysLoadFailed {
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load evidence day keys for \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("data-issue-scan-failed", level: .warning)
    struct DataIssueScanFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to scan for data issues: \(description)"
        }
    }

    @LogEvent("clear-year-failed", level: .warning)
    struct ClearYearFailed {
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to clear year \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("locations-load-failed", level: .warning)
    struct LocationsLoadFailed {
        @LogField("region", exposure: .restricted, kind: .location)
        var region: String
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load locations for \(region) in \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("day-locations-load-failed", level: .warning)
    struct DayLocationsLoadFailed {
        @LogField("day", exposure: .restricted, kind: .dateTime)
        var day: String
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load locations for day \(day) in \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.day(day)
        }
    }

    @LogEvent("representative-coordinates-load-failed", level: .warning)
    struct RepresentativeCoordinatesLoadFailed {
        @LogField("year", exposure: .restricted, kind: .domainValue)
        var year: Int
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load representative coordinates for \(year): \(description)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }
}
