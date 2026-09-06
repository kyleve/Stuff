import ThrowCore

extension ADSBExchangeUsageEstimate {
    var displayedRequestsPerHour: Int {
        Int(requestsPerHour.rounded(.up))
    }

    var displayedThirtyDayUpperBound: Int {
        Int(thirtyDayUpperBound.rounded(.up))
    }
}
