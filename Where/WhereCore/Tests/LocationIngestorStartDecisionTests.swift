import Testing
import WhereCore

struct LocationIngestorStartDecisionTests {
    @Test func completeSetupWhenMonitoringStillWanted() {
        #expect(
            LocationIngestorStart.afterLocationSourceStart(isMonitoring: true)
                == .completeSetup,
        )
    }

    @Test func abortWhenStopRanDuringLocationSourceStart() {
        #expect(
            LocationIngestorStart.afterLocationSourceStart(isMonitoring: false)
                == .abortMonitoringStoppedDuringAwait,
        )
    }
}
