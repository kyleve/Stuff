import Testing
@testable import WhereCore

struct RecordingReviewQueryTests {
    @Test func queryIdentityRetainsTargetDevicesAndSeparateReviewedPeriods() throws {
        let periods = try [
            RecordingAssessmentTestSupport.period(0, 1),
            RecordingAssessmentTestSupport.period(5, 6),
        ]
        let query = try RecordingReviewQuery(
            periods: periods,
            deviceIDs: [RecordingControlsTestSupport.device],
        )
        let anotherDevice = try RecordingReviewQuery(
            periods: periods,
            deviceIDs: [RecordingControlsTestSupport.otherDevice],
        )
        #expect(query != anotherDevice)
        #expect(query.periods == periods)
        #expect(try query.evidencePeriods().count == 1)
        #expect(throws: (any Error).self) {
            try RecordingReviewQuery(
                periods: RecordingControlsTestSupport.malformedPeriods(),
                deviceIDs: [],
            )
        }
    }
}
