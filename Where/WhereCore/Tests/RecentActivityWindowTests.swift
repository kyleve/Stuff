import Foundation
import Testing
@testable import WhereCore

/// Covers `RecentActivityWindow`'s interval math: the rolling look-backs and
/// the calendar-relative "year so far", using a fixed calendar/time zone so the
/// year boundary is deterministic regardless of where the test runs.
struct RecentActivityWindowTests {
    private static let now = WhereCoreTestSupport.iso("2026-05-02T12:00:00+00:00")

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let day: TimeInterval = 24 * 60 * 60

    @Test func dayIsARollingTwentyFourHours() {
        let interval = RecentActivityWindow.day.interval(now: Self.now, calendar: Self.calendar)
        #expect(interval.end == Self.now)
        #expect(interval.start == Self.now.addingTimeInterval(-Self.day))
    }

    @Test func weekIsARollingSevenDays() {
        let interval = RecentActivityWindow.week.interval(now: Self.now, calendar: Self.calendar)
        #expect(interval.end == Self.now)
        #expect(interval.start == Self.now.addingTimeInterval(-7 * Self.day))
    }

    @Test func monthIsARollingThirtyDays() {
        let interval = RecentActivityWindow.month.interval(now: Self.now, calendar: Self.calendar)
        #expect(interval.end == Self.now)
        #expect(interval.start == Self.now.addingTimeInterval(-30 * Self.day))
    }

    @Test func yearToDateStartsAtTheStartOfTheCalendarYear() {
        let interval = RecentActivityWindow.yearToDate
            .interval(now: Self.now, calendar: Self.calendar)
        #expect(interval.end == Self.now)
        #expect(interval.start == WhereCoreTestSupport.iso("2026-01-01T00:00:00+00:00"))
    }
}
