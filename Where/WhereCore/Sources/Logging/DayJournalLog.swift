import PeriscopeCore

/// Structured events for `DayJournal`'s committed writes. The affected calendar
/// day (or year) rides on `externalID` so the tooling can pull every event
/// about one day. All are successful-operation `.info` events.
enum DayJournalLog: LogEvent {
    /// Names the journal's timed spans: the writes whose cost scales with how
    /// much the user asked for, plus the reconcile fan-out every write pays.
    ///
    /// Single-row writes (one manual day, one override, one evidence record, one
    /// dismissal) aren't here — each is a `SwiftDataStore` commit followed by one
    /// of the fan-outs below, and both are already spanned, so a span of their
    /// own would only sum its two children.
    enum SpanName: Hashable {
        /// A bulk sample load in one transaction (fixtures, future imports).
        case ingestBatch
        /// A date-range manual-day backfill in one transaction.
        case backfillDays
        /// A multi-day overlay clear in one transaction.
        case clearManualDays
        /// Deleting a whole year of samples and overlays.
        case clearYear
        /// Emptying the store — the write half of the app's reset.
        case eraseAllData
        /// The reconcile every committed write pays: invalidate the issue
        /// scanner, then recount the badge and the issue notification.
        case reconcileIssueState
        /// ``reconcileIssueState`` plus the widget republish, for writes that
        /// changed day data. Nests the former, so the difference between the two
        /// spans is what WidgetKit cost.
        case reconcileAfterDayChange
    }

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
