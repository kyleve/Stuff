import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Regression guard for the reported bug: a manual day (override / backfill)
/// resolved in one time zone must stay resolved when the same store is read in
/// another, because it is keyed by a timezone-independent `CalendarDay` rather
/// than an absolute instant. Uses only manual days (no GPS) to isolate the
/// stored-record behavior.
struct TimeZoneIndependenceTests {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func reader(_ timeZone: TimeZone, store: any WhereStore) -> ReportReader {
        ReportReader(
            store: store,
            aggregator: DayAggregator(timeZone: timeZone),
            attributor: RegionAttributor.shared,
        )
    }

    @Test func backfilledDayStaysPresentWhenReadInAnotherTimeZone() async throws {
        let store = try SwiftDataStore.inMemory()

        // Log Feb 8 while the device is in New York. This mirrors what
        // `DayJournal.addManualDay` persists: the day the picked date lands on in
        // the writer's calendar, keyed by `CalendarDay`.
        let picked = try #require(calendar(newYork)
            .date(from: DateComponents(year: 2026, month: 2, day: 8, hour: 9)))
        let logged = CalendarDay(from: picked, in: calendar(newYork))
        try await store.perform {
            try await store.setManualDay(DayPresence(day: logged, regions: [.newYork]))
        }

        let feb8 = CalendarDay(year: 2026, month: 2, day: 8)
        #expect(logged == feb8)

        let nyReport = try await reader(newYork, store: store).yearReport(for: 2026)
        let pacificReport = try await reader(pacific, store: store).yearReport(for: 2026)

        // Present in both zones — the record didn't shift onto Feb 7 in Pacific.
        #expect(nyReport.days.map(\.day).contains(feb8))
        #expect(pacificReport.days.map(\.day).contains(feb8))

        // And it never re-surfaces as a missing day after the move to Pacific.
        let now = try #require(calendar(pacific).date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 1,
        )))
        let missing = pacificReport.missingDayKeys(asOf: now, calendar: calendar(pacific))
        #expect(!missing.contains(feb8))
    }

    @Test func dismissalKeyIsTimeZoneIndependent() {
        // The same logical day yields the same dismissal key regardless of any
        // calendar — dismissals no longer reappear after travel.
        let day = CalendarDay(year: 2026, month: 4, day: 1)
        #expect(DataIssueID.borderDrift(day: day).storageKey == "borderDrift:2026-04-01")
        #expect(
            DataIssueID.abruptChange(earlier: day, later: day.adding(days: 1)).storageKey
                == "abruptChange:2026-04-01:2026-04-02",
        )
    }
}
