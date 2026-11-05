import Testing
@testable import WhereCore

struct RecordingCalendarDecisionTests {
    @Test func rejectsMalformedPeriodsBeforeNormalization() throws {
        let source = try RecordingControlsTestSupport.calendar(1, action: .withdraw)
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try RecordingCalendarDecision(
                id: source.id,
                author: source.author,
                deviceID: source.deviceID,
                periods: RecordingControlsTestSupport.malformedPeriods(),
                action: source.action,
                predecessors: source.predecessors,
                version: source.version,
            )
        }
    }

    @Test func roundTripPreservesFixedOffsetAndCausalWithdrawal() throws {
        let first = try RecordingControlsTestSupport.calendar(
            1,
            action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
        )
        let withdrawal = try RecordingControlsTestSupport.calendar(
            2,
            action: .withdraw,
            predecessors: [first.id],
        )
        #expect(try RecordingControlsTestSupport.roundTrip(first) == first)
        #expect(try RecordingControlsTestSupport.roundTrip(withdrawal) == withdrawal)
    }
}
