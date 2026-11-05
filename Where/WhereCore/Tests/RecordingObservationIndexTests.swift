import Foundation
import Testing
@testable import WhereCore

struct RecordingObservationIndexTests {
    @Test func halfOpenLookupKeepsEveryEqualTimeObservation() throws {
        let observations = try fixture()
        let index = RecordingObservationIndex(observations.reversed())
        let included = try index.observations(in: RecordingAssessmentTestSupport.period(0, 10))
        #expect(included == Array(observations[2 ... 3]))
        #expect(index.observations == observations)
        #expect(try index.observations(in: RecordingAssessmentTestSupport.period(1, 10)).isEmpty)
    }

    @Test func contextIncludesItsPaddingEndpointButExcludesCoverageEnd() throws {
        let observations = try fixture()
        let index = RecordingObservationIndex(observations)
        let period = try RecordingAssessmentTestSupport.period(0, 10)
        let covered = try index.context(
            in: RecordingAssessmentTestSupport.period(-10, 20),
            around: period,
            padding: 10,
        )
        #expect(covered == Array(observations[1 ... 4]))
        let padded = try index.context(
            in: RecordingAssessmentTestSupport.period(-20, 30),
            around: period,
            padding: 10,
        )
        #expect(padded == Array(observations[1 ... 5]))
    }

    @Test func absentEvidenceAndDisjointContextStayEmpty() throws {
        let period = try RecordingAssessmentTestSupport.period(0, 10)
        #expect(RecordingObservationIndex([]).observations(in: period).isEmpty)
        let index = try RecordingObservationIndex(fixture())
        #expect(try index.context(
            in: period,
            around: RecordingAssessmentTestSupport.period(100, 101),
            padding: 10,
        ).isEmpty)
        #expect(try index.context(
            in: period,
            around: RecordingAssessmentTestSupport.period(-101, -100),
            padding: 10,
        ).isEmpty)
    }

    private func fixture() throws -> [RecordingObservation] {
        try [-20.0, -10, 0, 0, 10, 20, 30].enumerated().map { index, seconds in
            try RecordingAssessmentTestSupport.observation(
                seconds: seconds,
                sampleID: UUID(uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    index + 1,
                ))!,
            )
        }
    }
}
