import Foundation
import Testing
@testable import WhereCore

struct LocationHistoryQueryTests {
    @Test(arguments: [-18 * 3600, 18 * 3600])
    func logicalYearQueryIncludesOppositeUTCYearAtExtremeOffsets(offset: Int) throws {
        let days = CalendarDay.yearRange(2001)
        let query = LocationHistoryQuery.days(days)
        let zone = try #require(TimeZone(secondsFromGMT: offset))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let first = days.lowerBound.startOfDay(in: calendar)
        let last = days.upperBound.startOfDay(in: calendar).addingTimeInterval(86400 - 0.5)
        let period = try query.recordingPeriod()
        #expect(period.contains(first))
        #expect(period.contains(last))
        #expect(!period.contains(period.end))
    }

    @Test func selectedLogicalDayWinsOverTheViewingDateAndQueryYear() throws {
        let observation = try RecordingAssessmentTestSupport.observation(seconds: 0)
        let day = CalendarDay(year: 2000, month: 12, day: 31)
        let entry = AttributedLocationSample(
            sample: observation.sample,
            regions: [.california],
            day: .recording(day),
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(LocationHistoryQuery.days(CalendarDay.yearRange(2000)).contains(
            entry,
            viewingCalendar: calendar,
        ))
        #expect(!LocationHistoryQuery.days(CalendarDay.yearRange(2001)).contains(
            entry,
            viewingCalendar: calendar,
        ))
        #expect(try LocationHistoryQuery.instants(RecordingAssessmentTestSupport.period(0, 1))
            .contains(
                entry,
                viewingCalendar: calendar,
            ))
    }

    @Test(arguments: ["America/New_York", "America/Havana"])
    func viewingQueriesRetainDaylightSavingBoundaries(zone: String) throws {
        let day = CalendarDay(year: 2026, month: 3, day: 8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let period = try LocationHistoryQuery.days(day ... day).viewingPeriod(in: calendar)
        #expect(period.end.timeIntervalSince(period.start) == 23 * 3600)
        let nextDay = day.adding(days: 1).startOfDay(in: calendar)
        #expect(period.end == nextDay)
        #expect(!period.contains(nextDay.addingTimeInterval(1800)))
    }

    @Test func malformedLogicalDaysFailBeforeCalendarNormalization() {
        let day = CalendarDay(year: 2026, month: 2, day: 31)
        #expect(throws: RecordingDayCoverage.ValidationError.self) {
            try LocationHistoryQuery.days(day ... day).recordingPeriod()
        }
    }
}
