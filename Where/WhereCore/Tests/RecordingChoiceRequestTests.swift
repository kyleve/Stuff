import Testing
@testable import WhereCore

struct RecordingChoiceRequestTests {
    @Test func fixedChoicesKeepGapsAndReadAdjacentContext() throws {
        let periods = try [
            RecordingAssessmentTestSupport.period(0, 10),
            RecordingAssessmentTestSupport.period(20, 30),
        ]
        let request = RecordingChoiceRequest(
            scope: .periods(periods.reversed()),
            action: .automatic,
        )
        #expect(try request.searchPeriods() == periods)
        let evidence = try request.evidencePeriods()
        #expect(evidence.count == 1)
        #expect(evidence[0].start < periods[0].start)
        #expect(evidence[0].end > periods[1].end)
    }

    @Test func invalidFixedPeriodsAndAnotherDevicesLogicalDayAreRejected() throws {
        #expect(throws: (any Error).self) {
            try RecordingChoiceRequest(scope: .periods([]), action: .automatic).searchPeriods()
        }
        #expect(throws: (any Error).self) {
            try RecordingChoiceRequest(
                scope: .periods(RecordingControlsTestSupport.malformedPeriods()),
                action: .automatic,
            ).searchPeriods()
        }
        #expect(throws: DataCompatibilityError.conflictingRecord) {
            try RecordingChoiceRequest(
                scope: .recordingDay(
                    deviceID: RecordingControlsTestSupport.device,
                    day: .init(year: 2001, month: 1, day: 1),
                ),
                action: .select(RecordingControlsTestSupport.otherDevice),
            ).searchPeriods()
        }
    }
}
