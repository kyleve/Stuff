import Testing
@testable import WhereCore

struct HistoryDecisionTests {
    @Test func rejectsMalformedPeriodsBeforeNormalization() throws {
        let source = try RecordingAssessmentTestSupport.decision(1)
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try HistoryDecision(
                id: source.id,
                author: source.author,
                periods: RecordingControlsTestSupport.malformedPeriods(),
                scope: source.scope,
                action: source.action,
                predecessors: source.predecessors,
                version: source.version,
            )
        }
    }

    @Test func normalizesScopeWithoutJoiningSeparatedPeriods() throws {
        let decision = try HistoryDecision(
            id: RecordingAssessmentTestSupport.decisionID(1),
            author: RecordingAssessmentTestSupport.first,
            periods: [
                RecordingAssessmentTestSupport.period(20, 30),
                RecordingAssessmentTestSupport.period(0, 10),
                RecordingAssessmentTestSupport.period(5, 15),
            ],
            scope: .fixedPeriods,
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
