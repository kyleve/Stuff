import Foundation
import Testing
@testable import WhereCore

struct RecordingIntervalTests {
    @Test func ongoingValidityHasNoExpirationAndClipsToFiniteQueries() throws {
        let start = RecordingAssessmentTestSupport.time(20)
        let interval = try RecordingInterval(start: start, end: nil)
        #expect(!interval.contains(start.addingTimeInterval(-1)))
        #expect(interval.contains(start))
        #expect(interval.contains(Date(timeIntervalSinceReferenceDate: 1e12)))
        #expect(try RecordingControlsTestSupport.roundTrip(interval) == interval)
        #expect(try interval.intersection(RecordingAssessmentTestSupport.period(0, 20)) == nil)
        #expect(try interval.intersection(RecordingAssessmentTestSupport.period(0, 100)) ==
            RecordingAssessmentTestSupport.period(20, 100))
        let finite = try RecordingInterval(RecordingAssessmentTestSupport.period(20, 40))
        #expect(!finite.contains(RecordingAssessmentTestSupport.time(40)))
        #expect(interval.intersection(finite) == finite)
        #expect(finite.intersection(interval) == finite)
    }

    @Test func unionPreservesGapsAndOngoingTailsWithoutInventingBounds() throws {
        let time = RecordingAssessmentTestSupport.time
        let first = try RecordingInterval(start: time(0), end: time(10))
        let tail = try RecordingInterval(start: time(20), end: nil)
        let later = try RecordingInterval(start: time(30), end: time(50))
        #expect(RecordingInterval.union([later, tail, first]) == [first, tail])
        let bridge = try RecordingInterval(start: time(10), end: time(20))
        #expect(try RecordingInterval.union([tail, first, bridge]) == [
            RecordingInterval(start: time(0), end: nil),
        ])
        #expect(!first.overlaps(bridge))
        #expect(tail.overlaps(later))
        #expect(!tail.overlaps(first))
    }

    @Test func admissionRejectsInvalidBoundsRatherThanTreatingThemAsOngoing() throws {
        for end in [Double.nan, .infinity, -1, 0] {
            #expect(throws: RecordingInterval.ValidationError.self) {
                try RecordingInterval(
                    start: .init(timeIntervalSinceReferenceDate: 0),
                    end: .init(timeIntervalSinceReferenceDate: end),
                )
            }
        }
        #expect(throws: RecordingInterval.ValidationError.self) {
            try RecordingInterval(start: .init(timeIntervalSinceReferenceDate: .nan), end: nil)
        }
        let decoded = try JSONDecoder().decode(
            RecordingInterval.self,
            from: Data(#"{"start":20,"end":10}"#.utf8),
        )
        #expect(throws: RecordingInterval.ValidationError.self) { try decoded.validate() }
    }
}
