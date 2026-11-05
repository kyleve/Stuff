import Foundation
import Testing
@testable import WhereCore

struct RecordingDayAssignmentTests {
    @Test func aSavedCommonEraDayCannotValidateAnObservationInThePreviousEra() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let commonEra = try #require(calendar.date(from: DateComponents(
            era: 1,
            year: 1,
            month: 1,
            day: 1,
        )))
        let previousEra = try #require(calendar.date(from: DateComponents(
            era: 0,
            year: 1,
            month: 1,
            day: 1,
        )))
        let context = try RecordingDayAssignment.Context(observedAt: commonEra, timeZone: .gmt)
        let restored = try RecordingControlsTestSupport.roundTrip(context)
        #expect(restored.matches(observedAt: commonEra))
        #expect(!restored.matches(observedAt: previousEra))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonfiniteTimestamps(seconds: Double) throws {
        #expect(throws: RecordingDayAssignment.Context.ValidationError.self) {
            try RecordingDayAssignment.Context(
                observedAt: Date(timeIntervalSinceReferenceDate: seconds),
                timeZone: .gmt,
            )
        }
    }

    @Test func oneInstantCanHaveTwoRecordingDaysWithoutLosingItsZone() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-12-09T06:00:00Z"))
        let western = try RecordingDayAssignment.resolved(.init(
            observedAt: instant,
            timeZone: #require(TimeZone(identifier: "America/Los_Angeles")),
        ))
        let eastern = try RecordingDayAssignment.resolved(.init(
            observedAt: instant,
            timeZone: #require(TimeZone(identifier: "America/New_York")),
        ))
        #expect(western.day == CalendarDay(year: 2026, month: 12, day: 8))
        #expect(eastern.day == CalendarDay(year: 2026, month: 12, day: 9))
        #expect(RecordingDayAssignment.unresolved.day == nil)
    }
}
