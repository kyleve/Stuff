import Foundation
import Testing
@testable import WhereCore

struct RecordingCalendarContextTests {
    @Test func storedOffsetRemainsAuthoritativeAfterZoneRulesChange() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        // Simulate a historical zone rule that differs from the machine's current database.
        let context = try RecordingCalendarContext(timeZone: zone, secondsFromGMT: 3600)
        let observedAt = RecordingAssessmentTestSupport.time(-1800)
        let assignment = try RecordingDayAssignment.Context(
            observedAt: observedAt,
            calendarContext: context,
        )
        #expect(assignment.day == CalendarDay(year: 2001, month: 1, day: 1))
        #expect(assignment.timeZone == zone)
        #expect(assignment.matches(observedAt: observedAt))
        #expect(try RecordingControlsTestSupport.roundTrip(assignment) == assignment)
    }

    @Test func invalidWireOffsetFailsAdmission() throws {
        let valid = try RecordingCalendarContext(timeZone: .gmt, secondsFromGMT: 0)
        var wire = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        wire["secondsFromGMT"] = 1_000_000
        let context = try JSONDecoder().decode(
            RecordingCalendarContext.self,
            from: JSONSerialization.data(withJSONObject: wire),
        )
        #expect(throws: RecordingCalendarContext.ValidationError.self) { try context.validate() }
    }
}
