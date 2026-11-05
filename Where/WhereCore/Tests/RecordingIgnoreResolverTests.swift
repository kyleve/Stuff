import Foundation
import Testing
@testable import WhereCore

struct RecordingIgnoreResolverTests {
    private func resolve(
        _ decisions: [RecordingIgnoreDecision],
        end: Double = 86500,
    ) throws -> [RecordingIgnoreResolver.Segment] {
        try RecordingIgnoreResolver.resolve(
            decisions,
            for: RecordingControlsTestSupport.device,
            within: RecordingAssessmentTestSupport.period(0, end),
            version: RecordingControlsTestSupport.version,
        )
    }

    @Test func expiryFiltersHistoricalObservationTimesAndResumePreservesElapsedIgnore() throws {
        let initial = try RecordingControlsTestSupport.ignore(1)
        #expect(try resolve([initial]).map(\.resolution) == [.ignored, .eligible])
        let resumed = try RecordingControlsTestSupport.ignore(
            2,
            start: 50,
            change: .restoreEligibility,
            predecessors: [initial.id],
        )
        #expect(try resolve([resumed, initial]).map(\.resolution) == [
            .ignored,
            .eligible,
            .eligible,
        ])
        let undo = try RecordingControlsTestSupport.ignore(
            3,
            end: 50,
            change: .restoreEligibility,
            predecessors: [initial.id, resumed.id],
        )
        #expect(try resolve([undo, resumed, initial]).allSatisfy { $0.resolution == .eligible })
    }

    @Test func concurrentResumeAndIgnoreConflictOnlyInTheirOverlap() throws {
        let initial = try RecordingControlsTestSupport.ignore(1)
        let resumed = try RecordingControlsTestSupport.ignore(
            2,
            start: 50,
            change: .restoreEligibility,
        )
        #expect(try resolve([initial, resumed], end: 100).map(\.resolution) == [
            .ignored,
            .conflict([initial.id, resumed.id]),
        ])
        let expected = try resolve([initial, resumed])
        #expect(try resolve([resumed, initial, resumed]) == expected)
    }

    @Test func missingPredecessorsStayIncompleteAndCrossDevicePredecessorsAreInvalid() throws {
        let initial = try RecordingControlsTestSupport.ignore(1)
        let resumed = try RecordingControlsTestSupport.ignore(
            2,
            change: .restoreEligibility,
            predecessors: [initial.id],
        )
        #expect(try resolve([resumed], end: 100).map(\.resolution) == [.incomplete([initial.id])])
        let other = try RecordingControlsTestSupport.ignore(
            1,
            deviceID: RecordingControlsTestSupport.otherDevice,
        )
        #expect(throws: RecordingIgnoreResolver.ValidationError.invalidPredecessor(resumed.id)) {
            try resolve([resumed, other])
        }
    }

    @Test func concurrentEndDateEditsAgreeBeforeTheirEndsAndConflictOnlyOnTheRestoredTail() throws {
        let original = try RecordingControlsTestSupport.ignore(
            1,
            end: 3 * 86400,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 3), timeZone: .gmt)),
        )
        let short = try RecordingControlsTestSupport.ignore(
            2,
            end: 3 * 86400,
            predecessors: [original.id],
        )
        let medium = try RecordingControlsTestSupport.ignore(
            3,
            end: 3 * 86400,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 2), timeZone: .gmt)),
            predecessors: [original.id],
        )
        let expected = try resolve([original, short, medium], end: 3 * 86400)
        #expect(expected.map(\.resolution) == [
            .ignored,
            .conflict([short.id, medium.id]),
            .eligible,
        ])
        #expect(try resolve([medium, short, original, short], end: 3 * 86400) == expected)
        #expect(try resolve([short], end: 3 * 86400).allSatisfy {
            $0.resolution == .incomplete([original.id])
        })
        #expect(short.action(at: Date(timeIntervalSinceReferenceDate: 86400)) == .eligible)
        #expect(try RecordingControlsTestSupport.roundTrip(short) == short)
    }
}
