import PeriscopeCore

/// Structured events for `DayJournal`'s committed writes. The affected calendar
/// day (or year) rides on `externalID` so the tooling can pull every event
/// about one day. All are successful-operation `.info` events.
enum DayJournalLog: LogEvent {
    case addedManualDay(day: String, regionCount: Int)
    case overrodeDay(day: String, regionCount: Int)
    case clearedManualDay(day: String)
    case clearedManualDays(dayCount: Int)
    case backfilledManualDays(dayCount: Int, regionCount: Int)
    case clearedYear(year: Int)
    case erasedAllData
    case wroteEvidence(id: String, hasBlob: Bool)

    static let eventName = "DayJournal"

    var message: String {
        switch self {
            case let .addedManualDay(day, regionCount):
                "Added manual day \(day) with \(regionCount) region(s)"
            case let .overrodeDay(day, regionCount):
                "Overrode day \(day) with \(regionCount) region(s)"
            case let .clearedManualDay(day):
                "Cleared manual overlay for day \(day)"
            case let .clearedManualDays(dayCount):
                "Cleared manual overlays for \(dayCount) day(s)"
            case let .backfilledManualDays(dayCount, regionCount):
                "Backfilled \(dayCount) manual day(s) with \(regionCount) region(s)"
            case let .clearedYear(year):
                "Cleared year \(year)"
            case .erasedAllData:
                "Erased all store data"
            case let .wroteEvidence(id, hasBlob):
                "Wrote evidence \(id) (blob: \(hasBlob))"
        }
    }

    var externalID: String? {
        switch self {
            case let .addedManualDay(day, _), let .overrodeDay(day, _),
                 let .clearedManualDay(day):
                WhereStoreID.day(day)
            case let .clearedYear(year):
                WhereStoreID.year(year)
            case let .wroteEvidence(id, _):
                WhereStoreID.evidence(id)
            case .clearedManualDays, .backfilledManualDays, .erasedAllData:
                nil
        }
    }
}
