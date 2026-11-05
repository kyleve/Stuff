import Testing
@testable import WhereCore

struct RecordingPlaceDecisionTests {
    @Test func rejectsMalformedPeriodsBeforeNormalization() throws {
        let source = try RecordingControlsTestSupport.place(1)
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try RecordingPlaceDecision(
                id: source.id,
                author: source.author,
                placeID: source.placeID,
                periods: RecordingControlsTestSupport.malformedPeriods(),
                action: source.action,
                predecessors: source.predecessors,
                version: source.version,
            )
        }
    }

    @Test func roundTripPreservesPlaceIdentityAndRemoval() throws {
        let place = try RecordingControlsTestSupport.place(1)
        let removal = try RecordingControlsTestSupport.place(
            2,
            action: .remove,
            predecessors: [place.id],
        )
        #expect(try RecordingControlsTestSupport.roundTrip(place) == place)
        #expect(try RecordingControlsTestSupport.roundTrip(removal) == removal)
    }

    @Test func rejectsInvalidLocation() {
        #expect(throws: RecordingPlace.ValidationError.self) {
            try RecordingControlsTestSupport.place(
                1,
                action: .set(kind: .temporaryBase, coordinate: .init(latitude: 91, longitude: 0)),
            )
        }
    }
}
