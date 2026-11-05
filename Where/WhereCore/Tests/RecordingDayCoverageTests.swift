import Foundation
import Testing
@testable import WhereCore

struct RecordingDayCoverageTests {
    @Test(arguments: ["2026-03-08": 23, "2026-11-01": 25])
    func followsDaylightSavingWithoutAssumingTwentyFourHours(day: String, hours: Int) throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let logicalDay = try #require(CalendarDay(iso: day))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = logicalDay.startOfDay(in: calendar)
        let search = try RecordingPeriod(
            start: start.addingTimeInterval(-3600),
            end: start.addingTimeInterval(27 * 3600),
        )
        let result = try RecordingDayCoverage.resolve(
            day: logicalDay,
            within: search,
            contexts: [
                .init(
                    period: RecordingPeriod(
                        start: search.start,
                        end: start.addingTimeInterval(2 * 3600),
                    ),
                    calendarContext: .init(observedAt: search.start, timeZone: zone),
                ),
                .init(
                    period: RecordingPeriod(
                        start: start.addingTimeInterval(2 * 3600),
                        end: search.end,
                    ),
                    calendarContext: .init(
                        observedAt: start.addingTimeInterval(2 * 3600),
                        timeZone: zone,
                    ),
                ),
            ],
        )
        #expect(try result == .resolved([RecordingPeriod(
            start: start,
            end: start.addingTimeInterval(Double(hours) * 3600),
        )]))
    }

    @Test func aRepeatedDateHasDisjointCoverageWithoutIncludingTheInterveningDay() throws {
        let utc = TimeZone.gmt
        let earlier = try #require(TimeZone(secondsFromGMT: -12 * 3600))
        let start = try #require(ISO8601DateFormatter().date(from: "2026-12-08T00:00:00Z"))
        func hour(_ value: Double) -> Date {
            start.addingTimeInterval(value * 3600)
        }
        let search = try RecordingPeriod(start: hour(0), end: hour(36))
        let result = try RecordingDayCoverage.resolve(
            day: CalendarDay(year: 2026, month: 12, day: 8),
            within: search,
            contexts: [
                .init(
                    period: RecordingPeriod(start: hour(0), end: hour(30)),
                    calendarContext: .init(observedAt: start, timeZone: utc),
                ),
                .init(
                    period: RecordingPeriod(start: hour(30), end: hour(36)),
                    calendarContext: .init(observedAt: start, timeZone: earlier),
                ),
            ],
        )
        #expect(try result == .resolved([
            RecordingPeriod(start: hour(0), end: hour(24)),
            RecordingPeriod(start: hour(30), end: hour(36)),
        ]))
    }

    @Test func missingCalendarContextRequiresClarificationRegardlessOfGPS() throws {
        let result = try RecordingDayCoverage.resolve(
            day: CalendarDay(year: 2001, month: 1, day: 1),
            within: RecordingAssessmentTestSupport.period(0, 100),
            contexts: [.init(
                period: RecordingAssessmentTestSupport.period(0, 40),
                calendarContext: .init(timeZone: .gmt, secondsFromGMT: 0),
            )],
        )
        #expect(try result == .needsContext([RecordingAssessmentTestSupport.period(40, 100)]))
    }

    @Test func conflictingCalendarContextsFailInsteadOfSelectingByInputOrder() throws {
        let period = try RecordingAssessmentTestSupport.period(0, 100)
        #expect(throws: RecordingDayCoverage.ValidationError.self) {
            try RecordingDayCoverage.resolve(
                day: CalendarDay(year: 2001, month: 1, day: 1),
                within: period,
                contexts: [
                    .init(
                        period: period,
                        calendarContext: .init(timeZone: .gmt, secondsFromGMT: 0),
                    ),
                    .init(
                        period: period,
                        calendarContext: .init(
                            timeZone: #require(TimeZone(secondsFromGMT: 3600)),
                            secondsFromGMT: 3600,
                        ),
                    ),
                ],
            )
        }
    }
}
