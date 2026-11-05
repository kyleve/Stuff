import Testing
@testable import WhereCore

struct RecordingCalendarResolverTests {
    private func resolve(_ decisions: [RecordingCalendarDecision]) throws
        -> [RecordingCalendarResolver.Segment]
    {
        try RecordingCalendarResolver.resolve(
            decisions,
            for: RecordingControlsTestSupport.device,
            within: RecordingAssessmentTestSupport.period(0, 100),
            version: RecordingControlsTestSupport.version,
        )
    }

    @Test func withdrawalDoesNotGuessContextOrRewriteEarlierIntervals() throws {
        let context = try RecordingCalendarContext(timeZone: .gmt, secondsFromGMT: 0)
        let first = try RecordingControlsTestSupport.calendar(1, action: .establish(context))
        let withdrawal = try RecordingControlsTestSupport.calendar(
            2,
            start: 50,
            action: .withdraw,
            predecessors: [first.id],
        )
        #expect(try resolve([withdrawal, first]).map(\.resolution) == [
            .established(context),
            .unknown,
        ])
        #expect(try resolve([withdrawal]).map(\.resolution) == [.unknown, .incomplete([first.id])])
    }

    @Test func concurrentCalendarEditsRequireReviewAndCannotSupersedeAnotherDevice() throws {
        let first = try RecordingControlsTestSupport.calendar(
            1,
            action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
        )
        let second = try RecordingControlsTestSupport.calendar(
            2,
            action: .establish(.init(timeZone: .gmt, secondsFromGMT: 3600)),
        )
        #expect(try resolve([second, first]).map(\.resolution) == [.conflict([
            first.id,
            second.id,
        ])])
        let invalid = try RecordingControlsTestSupport.calendar(
            3,
            action: .withdraw,
            predecessors: [first.id],
        )
        let other = try RecordingControlsTestSupport.calendar(
            1,
            action: .withdraw,
            deviceID: RecordingControlsTestSupport.otherDevice,
        )
        #expect(throws: RecordingCalendarResolver.ValidationError.invalidPredecessor(invalid.id)) {
            try resolve([
                invalid,
                other,
            ])
        }
    }
}
