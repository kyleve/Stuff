import Testing
@testable import WhereCore

struct RecordingPlaceResolverTests {
    private func resolve(_ decisions: [RecordingPlaceDecision]) throws
        -> [RecordingPlaceResolver.Segment]
    {
        try RecordingPlaceResolver.resolve(
            decisions,
            for: RecordingControlsTestSupport.placeID,
            within: RecordingAssessmentTestSupport.period(0, 100),
            version: RecordingControlsTestSupport.version,
        )
    }

    @Test func changedAddressDoesNotRewriteEarlierValidityAndDeleteIsBounded() throws {
        let earlier = try RecordingControlsTestSupport.place(1)
        let later = try RecordingControlsTestSupport.place(
            2,
            start: 50,
            action: .set(kind: .regularHome, coordinate: .init(latitude: 40, longitude: -74)),
            predecessors: [earlier.id],
        )
        let deleted = try RecordingControlsTestSupport.place(
            3,
            start: 75,
            action: .remove,
            predecessors: [later.id],
        )
        let segments = try resolve([deleted, earlier, later])
        guard case let .place(first) = segments[0].resolution,
              case let .place(second) = segments[1].resolution
        else {
            Issue.record("Expected both historical addresses")
            return
        }
        #expect(first.coordinate.latitude == 37)
        #expect(second.coordinate.latitude == 40)
        #expect(first.validity.end == RecordingAssessmentTestSupport.time(50))
        #expect(segments[2].resolution == .absent)
    }

    @Test func concurrentChangesAndPartialDeliveryDoNotSelectAnAddressByTimestamp() throws {
        let first = try RecordingControlsTestSupport.place(1)
        let second = try RecordingControlsTestSupport.place(2, action: .remove)
        #expect(try resolve([second, first]).map(\.resolution) == [.conflict([
            first.id,
            second.id,
        ])])
        let replacement = try RecordingControlsTestSupport.place(
            3,
            predecessors: [first.id, second.id],
        )
        #expect(try resolve([replacement, second]).map(\.resolution) == [.incomplete([first.id])])
        #expect(try resolve([replacement, second, first]) == resolve([
            first,
            second,
            replacement,
            first,
        ]))
    }
}
