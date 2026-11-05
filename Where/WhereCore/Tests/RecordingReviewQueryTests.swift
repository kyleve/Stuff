import Testing
@testable import WhereCore

struct RecordingReviewQueryTests {
    @Test func combinedQueriesRetainSeparateFiniteHistoryAndOngoingPlaceScopes() throws {
        let period = try RecordingAssessmentTestSupport.period(0, 10)
        let home = try RecordingInterval(start: RecordingAssessmentTestSupport.time(20), end: nil)
        let finite = try RecordingReviewQuery(
            periods: [period],
            deviceIDs: [RecordingControlsTestSupport.device],
        )
        let place = try RecordingReviewQuery(
            placeID: RecordingControlsTestSupport.placeID,
            validity: [home],
        )
        let combined = try RecordingReviewQuery.combining([place, finite, place])
        #expect(combined.periods == [period])
        #expect(combined.deviceIDs == finite.deviceIDs)
        #expect(combined.places == place.places)
        #expect(try combined.evidencePeriods() == finite.evidencePeriods())
        #expect(try combined.intervals == [RecordingInterval(period), home])
        #expect(throws: DataCompatibilityError.incompleteRecord) {
            try RecordingReviewQuery(placeID: RecordingControlsTestSupport.placeID, validity: [])
        }
    }

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
