import Foundation
import Testing
@testable import WhereCore

struct CausalPeriodResolverTests {
    @Test func malformedWirePeriodsFailBeforeTheyCanClaimHistory() throws {
        let value = try RecordingAssessmentTestSupport.decision(1)
        let encoded = try JSONEncoder().encode(value)
        var wire = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        wire["periods"] = [["start": 20, "end": 10]]
        let decoded = try JSONDecoder().decode(
            HistoryDecision.self,
            from: JSONSerialization.data(withJSONObject: wire),
        )
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try CausalPeriodResolver<HistoryDecision>.resolve(
                [decoded],
                within: RecordingAssessmentTestSupport.period(0, 100),
            )
        }
    }
}
