import Foundation

public struct ADSBExchangeUsageEstimate: Equatable, Sendable {
    public let requestsPerHour: Double
    public let thirtyDayUpperBound: Double
    public let activeHoursCoveredByAllowance: Double
    public let exceedsPublishedAllowance: Bool

    public init(
        requestsPerHour: Double,
        thirtyDayUpperBound: Double,
        activeHoursCoveredByAllowance: Double,
        exceedsPublishedAllowance: Bool,
    ) {
        self.requestsPerHour = requestsPerHour
        self.thirtyDayUpperBound = thirtyDayUpperBound
        self.activeHoursCoveredByAllowance = activeHoursCoveredByAllowance
        self.exceedsPublishedAllowance = exceedsPublishedAllowance
    }
}

public enum ADSBExchangeUsageEstimator {
    public static let publishedPersonalPlanAllowance = 10000.0

    public static func estimate(
        pollingInterval: PollingInterval,
        quietSchedule: QuietSchedule,
    ) -> ADSBExchangeUsageEstimate {
        let requestsPerHour = 3600 / Double(pollingInterval.seconds)
        let quietMinutes = quietSchedule.interval?.durationMinutes ?? 0
        let activeHoursPerDay = Double(24 * 60 - quietMinutes) / 60
        let thirtyDayUpperBound = requestsPerHour * activeHoursPerDay * 30
        return ADSBExchangeUsageEstimate(
            requestsPerHour: requestsPerHour,
            thirtyDayUpperBound: thirtyDayUpperBound,
            activeHoursCoveredByAllowance: publishedPersonalPlanAllowance / requestsPerHour,
            exceedsPublishedAllowance: thirtyDayUpperBound > publishedPersonalPlanAllowance,
        )
    }
}
