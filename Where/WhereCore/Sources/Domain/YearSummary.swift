public struct YearSummary: Equatable, Sendable {
    public let year: Int
    public let totalsByJurisdiction: [TaxJurisdiction: Int]
    public let unknownDayCount: Int
    public let totalTrackedDays: Int

    public init(
        year: Int,
        totalsByJurisdiction: [TaxJurisdiction: Int],
        unknownDayCount: Int,
        totalTrackedDays: Int,
    ) {
        self.year = year
        self.totalsByJurisdiction = totalsByJurisdiction
        self.unknownDayCount = unknownDayCount
        self.totalTrackedDays = totalTrackedDays
    }
}
