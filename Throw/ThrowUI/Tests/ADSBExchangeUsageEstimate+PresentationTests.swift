import Testing
import ThrowCore
@testable import ThrowUI

struct ADSBExchangeUsageEstimatePresentationTests {
    @Test func roundsRequestEstimatesUpForIntegerPresentation() {
        let estimate = ADSBExchangeUsageEstimate(
            requestsPerHour: 514.2,
            thirtyDayUpperBound: 12345.1,
            activeHoursCoveredByAllowance: 19.4,
            exceedsPublishedAllowance: true,
        )

        #expect(estimate.displayedRequestsPerHour == 515)
        #expect(estimate.displayedThirtyDayUpperBound == 12346)
    }
}
