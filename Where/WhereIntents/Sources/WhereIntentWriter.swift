import Foundation
import RegionKit
import WhereCore

/// The write half of the App Intents layer: records user-asserted days through
/// `WhereServices.journal`, stamping each entry with a "Logged with Siri" audit
/// and no captured location (intents don't run GPS). A thin, testable value the
/// action intents delegate to.
struct WhereIntentWriter {
    let services: WhereServices
    var calendar = Calendar.whereIntents
    var now: @Sendable () -> Date = { Date() }

    /// Additively record `regions` for the calendar day containing `date`
    /// (unions with any GPS/manual data already there).
    func logDay(date: Date, regions: Set<Region>) async throws {
        try await services.journal.addManualDay(date: date, regions: regions, audit: makeAudit())
    }

    /// Backfill every calendar day in the inclusive range `start...end` with
    /// `regions`. Returns the number of days written (0 for an empty or inverted
    /// range, which writes nothing), so the intent can report it.
    @discardableResult
    func logTrip(from start: Date, through end: Date, regions: Set<Region>) async throws -> Int {
        let days = start.calendarDays(through: end, in: calendar)
        guard !days.isEmpty else { return 0 }
        try await services.journal.addManualDays(
            from: start,
            through: end,
            regions: regions,
            audit: makeAudit(),
        )
        return days.count
    }

    private func makeAudit() -> ManualEntryAudit {
        ManualEntryAudit(recordedAt: now(), note: IntentStrings.manualEntryNote, location: nil)
    }
}
