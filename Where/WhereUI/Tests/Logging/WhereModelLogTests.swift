import Testing
@testable import WhereUI

struct WhereModelLogTests {
    @Test func everyEventHasAStableDistinctName() {
        let names = [
            WhereModelLog.OnboardingCompleted.eventName,
            WhereModelLog.OpenedRealScope.eventName,
            WhereModelLog.StartedSession.eventName,
            WhereModelLog.EndedSession.eventName,
            WhereModelLog.ResetPreferences.eventName,
            WhereModelLog.EnteredDemoMode.eventName,
            WhereModelLog.ExitedDemoMode.eventName,
        ]
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.hasPrefix("WhereModel.") })
    }
}
