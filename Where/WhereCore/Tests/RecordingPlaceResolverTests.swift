import Testing
@testable import WhereCore

struct RecordingPlaceResolverTests {
    @Test func changedAndEndedHomesKeepEarlierAddressesAndResolveAnOngoingTail() throws {
        let original = try RecordingControlsTestSupport.place(1, end: nil)
        let changed = try RecordingControlsTestSupport.place(
            2,
            start: 50,
            end: nil,
            action: .set(
                kind: .regularHome,
                coordinate: .init(
                    latitude: 40,
                    longitude: -74,
                ),
            ),
            predecessors: [original.id],
        )
        let ended = try RecordingControlsTestSupport.place(
            3,
            start: 100,
            end: nil,
            action: .remove,
            predecessors: [changed.id],
        )
        let query = try RecordingInterval(start: RecordingAssessmentTestSupport.time(0), end: nil)
        let result = try RecordingPlaceResolver.resolve(
            [ended, changed, original],
            for: original.placeID,
            within: query,
            version: original.version,
        )
        #expect(result.count == 3)
        #expect(result[0].period.end == RecordingAssessmentTestSupport.time(50))
        #expect(result[1].period.end == RecordingAssessmentTestSupport.time(100))
        #expect(result[2].period.end == nil)
        #expect(result[2].resolution == .absent)
        #expect(result.map { RecordingPlaceInspection.Definition($0.resolution) } == [
            .place(kind: .regularHome, coordinate: .init(latitude: 37, longitude: -122)),
            .place(kind: .regularHome, coordinate: .init(latitude: 40, longitude: -74)),
            .absent,
        ])
        let later = try RecordingPlaceResolver.resolve(
            [changed, original],
            for: original.placeID,
            within: RecordingAssessmentTestSupport
                .period(
                    1e8,
                    1e8 + 100,
                ),
            version: original.version,
        )
        #expect(later.count == 1)
        #expect(later[0].period.end == RecordingAssessmentTestSupport.time(1e8 + 100))
        #expect(RecordingPlaceInspection.Definition(later[0].resolution) ==
            RecordingPlaceInspection.Definition(result[1].resolution))
    }

    @Test func concurrentAndMissingOngoingDefinitionsNeverChooseByDeliveryOrder() throws {
        let home = try RecordingControlsTestSupport.place(1, end: nil)
        let removal = try RecordingControlsTestSupport.place(
            2,
            start: 100,
            end: nil,
            action: .remove,
        )
        let query = try RecordingInterval(start: RecordingAssessmentTestSupport.time(0), end: nil)
        let conflict = try RecordingPlaceResolver.resolve(
            [removal, home],
            for: home.placeID,
            within: query,
            version: home.version,
        )
        #expect(conflict.last?.resolution == .conflict([home.id, removal.id]))
        #expect(conflict.last?.period.end == nil)
        let replacement = try RecordingControlsTestSupport.place(
            3,
            start: 100,
            end: nil,
            predecessors: [
                home.id,
                removal.id,
            ],
        )
        let partial = try RecordingPlaceResolver.resolve(
            [replacement, home],
            for: home.placeID,
            within: query,
            version: home.version,
        )
        #expect(partial.last?.resolution == .incomplete([removal.id]))
        let complete = try RecordingPlaceResolver.resolve(
            [replacement, removal, home],
            for: home.placeID,
            within: query,
            version: home.version,
        )
        #expect(try complete == RecordingPlaceResolver.resolve(
            [home, removal, replacement],
            for: home.placeID,
            within: query,
            version: home.version,
        ))
        #expect(complete.last?.effectiveDecisions == [replacement.id])
    }

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
