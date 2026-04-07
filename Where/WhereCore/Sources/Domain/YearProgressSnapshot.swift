public struct YearProgressSnapshot: Equatable, Sendable {
    public struct JurisdictionSummary: Identifiable, Equatable, Sendable {
        public let jurisdiction: TaxJurisdiction
        public let totalDays: Int

        public init(jurisdiction: TaxJurisdiction, totalDays: Int) {
            self.jurisdiction = jurisdiction
            self.totalDays = totalDays
        }

        public var id: TaxJurisdiction {
            jurisdiction
        }
    }

    public struct RecentDay: Identifiable, Equatable, Sendable {
        public let dateLabel: String
        public let jurisdictions: [TaxJurisdiction]
        public let note: String?

        public init(
            dateLabel: String,
            jurisdictions: [TaxJurisdiction],
            note: String? = nil,
        ) {
            self.dateLabel = dateLabel
            self.jurisdictions = jurisdictions
            self.note = note
        }

        public var id: String {
            dateLabel
        }
    }

    public let year: Int
    public let primarySummaries: [JurisdictionSummary]
    public let secondarySummaries: [JurisdictionSummary]
    public let trackingStatus: TrackingStatus
    public let recentDays: [RecentDay]

    public init(
        year: Int,
        primarySummaries: [JurisdictionSummary],
        secondarySummaries: [JurisdictionSummary],
        trackingStatus: TrackingStatus,
        recentDays: [RecentDay],
    ) {
        self.year = year
        self.primarySummaries = primarySummaries
        self.secondarySummaries = secondarySummaries
        self.trackingStatus = trackingStatus
        self.recentDays = recentDays
    }
}
