import Foundation
import Testing
@testable import WhereCore

struct RecordingPeriodTests {
    @Test func endpointsAreHalfOpenAndAdjacentPeriodsDoNotOverlap() throws {
        let left = try RecordingAssessmentTestSupport.period(0, 10)
        let right = try RecordingAssessmentTestSupport.period(10, 20)
        #expect(left.contains(RecordingAssessmentTestSupport.time(0)))
        #expect(left.contains(RecordingAssessmentTestSupport.time(10)) == false)
        #expect(right.contains(RecordingAssessmentTestSupport.time(10)))
        #expect(left.overlaps(right) == false)
        #expect(left.intersection(right) == nil)
    }

    @Test func unionPreservesGapsAndIntersectionClipsBothEnds() throws {
        let periods = try [
            RecordingAssessmentTestSupport.period(0, 10),
            RecordingAssessmentTestSupport.period(5, 15),
            RecordingAssessmentTestSupport.period(20, 30),
        ]
        #expect(try RecordingPeriod.union(periods.reversed()) == [
            RecordingAssessmentTestSupport.period(0, 15),
            RecordingAssessmentTestSupport.period(
                20,
                30,
            ),
        ])
        #expect(try RecordingAssessmentTestSupport.period(0, 10)
            .intersection(RecordingAssessmentTestSupport.period(
                5,
                15,
            )) == RecordingAssessmentTestSupport.period(5, 10))
    }

    @Test(arguments: [0.0, -1.0, Double.infinity, Double.nan])
    func rejectsInvalidEnd(_ end: Double) {
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try RecordingAssessmentTestSupport.period(0, end)
        }
    }
}
