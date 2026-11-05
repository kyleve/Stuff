import Foundation
import Testing
@testable import WhereCore

struct RecordingIgnoreDecisionTests {
    @Test func rejectsMalformedPeriodsBeforeNormalization() throws {
        let source = try RecordingControlsTestSupport.ignore(1)
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try RecordingIgnoreDecision(
                id: source.id,
                author: source.author,
                deviceID: source.deviceID,
                periods: RecordingControlsTestSupport.malformedPeriods(),
                change: source.change,
                predecessors: source.predecessors,
                version: source.version,
            )
        }
    }

    @Test(arguments: ["2026-03-08": 23, "2026-11-01": 25])
    func untilIncludesTheSelectedDayAcrossDST(day: String, hours: Int) throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let day = try #require(CalendarDay(iso: day))
        let until = try RecordingIgnoreDecision.Until(day: day, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(until.end.timeIntervalSince(day.startOfDay(in: calendar)) == Double(hours) * 3600)
        #expect(try RecordingControlsTestSupport.roundTrip(until) == until)
    }

    @Test func rejectsSkippedDateAndMismatchedEnd() throws {
        #expect(throws: RecordingIgnoreDecision.ValidationError.self) {
            try RecordingIgnoreDecision.Until(
                day: .init(year: 2011, month: 12, day: 30),
                timeZone: #require(TimeZone(identifier: "Pacific/Apia")),
            )
        }
        #expect(throws: RecordingIgnoreDecision.ValidationError.self) {
            try RecordingControlsTestSupport.ignore(1, end: 100)
        }
    }

    @Test func roundTripPreservesOperationIdentityPredecessorsAndFixedBoundary() throws {
        let initial = try RecordingControlsTestSupport.ignore(1)
        let resumed = try RecordingControlsTestSupport.ignore(
            2,
            start: 50,
            change: .restoreEligibility,
            predecessors: [initial.id],
        )
        #expect(try RecordingControlsTestSupport.roundTrip(initial) == initial)
        #expect(try RecordingControlsTestSupport.roundTrip(resumed) == resumed)
    }

    @Test func wireEndMustMatchItsSavedCalendarDayWithoutRecomputingZoneRules() throws {
        let until = try RecordingIgnoreDecision.Until(
            day: .init(year: 2001, month: 1, day: 1),
            timeZone: .gmt,
        )
        var wire = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(until)) as? [String: Any])
        wire["end"] = until.end.timeIntervalSinceReferenceDate + 3600
        let invalid = try JSONDecoder().decode(
            RecordingIgnoreDecision.Until.self,
            from: JSONSerialization.data(withJSONObject: wire),
        )
        #expect(throws: RecordingIgnoreDecision.ValidationError.self) { try invalid.validate() }
    }
}
