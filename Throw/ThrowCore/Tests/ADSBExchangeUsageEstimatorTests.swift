import Testing
@testable import ThrowCore

struct ADSBExchangeUsageEstimatorTests {
    @Test(arguments: [(5, 720.0), (10, 360.0), (300, 12.0)])
    func computesRequestsPerHour(seconds: Int, expected: Double) throws {
        let estimate = try ADSBExchangeUsageEstimator.estimate(
            pollingInterval: PollingInterval(seconds: seconds),
            quietSchedule: .disabled,
        )
        #expect(estimate.requestsPerHour == expected)
    }

    @Test func tenSecondsCoversAboutTwentySevenPointEightActiveHours() throws {
        let estimate = try ADSBExchangeUsageEstimator.estimate(
            pollingInterval: PollingInterval(seconds: 10),
            quietSchedule: .disabled,
        )
        #expect(abs(estimate.activeHoursCoveredByAllowance - 27.777_777) < 0.001)
        #expect(estimate.exceedsPublishedAllowance)
    }

    @Test func fiveMinutesIsEightThousandSixHundredFortyRequestsInThirtyDays() throws {
        let estimate = try ADSBExchangeUsageEstimator.estimate(
            pollingInterval: PollingInterval(seconds: 300),
            quietSchedule: .disabled,
        )
        #expect(estimate.thirtyDayUpperBound == 8640)
        #expect(estimate.exceedsPublishedAllowance == false)
    }

    @Test func quietIntervalReducesUpperBound() throws {
        let schedule = try QuietSchedule(
            start: LocalTime(hour: 0, minute: 0),
            end: LocalTime(hour: 12, minute: 0),
        )
        let estimate = try ADSBExchangeUsageEstimator.estimate(
            pollingInterval: PollingInterval(seconds: 300),
            quietSchedule: schedule,
        )
        #expect(estimate.thirtyDayUpperBound == 4320)
    }
}
