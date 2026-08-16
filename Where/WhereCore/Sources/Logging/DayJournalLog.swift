import PeriscopeCore

/// Structured events and spans for `DayJournal`.
@LogScope("DayJournal")
enum DayJournalLog {
    enum SpanName: Hashable {
        case ingestBatch
        case backfillDays
        case clearManualDays
        case clearYear
        case eraseAllData
        case reconcileIssueState
        case reconcileAfterDayDataChange
    }

    @LogEvent("added-manual-day")
    struct AddedManualDay {
        @LogField("day", exposure: .restricted, kind: .dateTime) var day: String
        @LogField("region_count", exposure: .shareable, kind: .count) var regionCount: Int
        var message: String {
            "Added manual day \(day) with \(regionCount) region(s)"
        }

        var externalID: String? {
            WhereStoreID.day(day)
        }
    }

    @LogEvent("overrode-day")
    struct OverrodeDay {
        @LogField("day", exposure: .restricted, kind: .dateTime) var day: String
        @LogField("region_count", exposure: .shareable, kind: .count) var regionCount: Int
        var message: String {
            "Overrode day \(day) with \(regionCount) region(s)"
        }

        var externalID: String? {
            WhereStoreID.day(day)
        }
    }

    @LogEvent("cleared-manual-day")
    struct ClearedManualDay {
        @LogField("day", exposure: .restricted, kind: .dateTime) var day: String
        var message: String {
            "Cleared manual overlay for day \(day)"
        }

        var externalID: String? {
            WhereStoreID.day(day)
        }
    }

    @LogEvent("cleared-manual-days")
    struct ClearedManualDays {
        @LogField("day_count", exposure: .shareable, kind: .count) var dayCount: Int
        var message: String {
            "Cleared manual overlays for \(dayCount) day(s)"
        }
    }

    @LogEvent("backfilled-manual-days")
    struct BackfilledManualDays {
        @LogField("day_count", exposure: .shareable, kind: .count) var dayCount: Int
        @LogField("region_count", exposure: .shareable, kind: .count) var regionCount: Int
        var message: String {
            "Backfilled \(dayCount) manual day(s) with \(regionCount) region(s)"
        }
    }

    @LogEvent("cleared-year")
    struct ClearedYear {
        @LogField("year", exposure: .restricted, kind: .domainValue) var year: Int
        var message: String {
            "Cleared year \(year)"
        }

        var externalID: String? {
            WhereStoreID.year(year)
        }
    }

    @LogEvent("erased-all-data", message: "Erased all store data")
    struct ErasedAllData {}

    @LogEvent("wrote-evidence")
    struct WroteEvidence {
        @LogField("id", exposure: .restricted, kind: .identifier) var id: String
        @LogField("has_blob", exposure: .shareable, kind: .boolean) var hasBlob: Bool
        var message: String {
            "Wrote evidence \(id) (blob: \(hasBlob))"
        }

        var externalID: String? {
            WhereStoreID.evidence(id)
        }
    }
}
