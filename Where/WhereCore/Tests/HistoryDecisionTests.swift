import Testing
@testable import WhereCore

struct HistoryDecisionTests {
    @Test func normalizesScopeWithoutJoiningSeparatedPeriods() throws {
        let decision = try HistoryDecision(
            id: RecordingAssessmentTestSupport.decisionID(1),
            author: RecordingAssessmentTestSupport.first,
            periods: [
                RecordingAssessmentTestSupport.period(20, 30),
                RecordingAssessmentTestSupport.period(0, 10),
                RecordingAssessmentTestSupport.period(5, 15),
            ],
            action: .automatic,
            predecessors: [],
            version: RecordingAssessmentTestSupport.version,
        )
        #expect(try decision.periods == [
            RecordingAssessmentTestSupport.period(0, 15),
            RecordingAssessmentTestSupport.period(20, 30),
        ])
    }
}
