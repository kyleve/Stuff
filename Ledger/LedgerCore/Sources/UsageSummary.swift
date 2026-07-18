import Foundation

/// The decoded `GET /api/usage-summary` response — the current billing cycle's
/// dates, plan type, and live usage/spend for an individual account.
///
/// Only the fields Ledger reads are modeled; synthesized `Codable` ignores the
/// rest. Cent amounts are integers here (the dashboard reports whole cents).
public struct UsageSummary: Codable, Equatable, Sendable {
    /// ISO-8601 start of the current billing cycle (kept as the wire string;
    /// see ``cycleStart``).
    public var billingCycleStart: String
    /// ISO-8601 end of the current billing cycle.
    public var billingCycleEnd: String
    /// `"pro"`, `"ultra"`, `"free"`, etc.
    public var membershipType: String
    public var individualUsage: IndividualUsage
    /// The dashboard's own human-readable status lines, when present (e.g.
    /// "You've used 21% of your included total usage").
    public var autoModelSelectedDisplayMessage: String? = nil
    public var namedModelSelectedDisplayMessage: String? = nil

    public struct IndividualUsage: Codable, Equatable, Sendable {
        /// Usage-based (pay-per-use) spend — the money beyond the subscription.
        public var onDemand: OnDemand
        /// Usage against the plan's included allowance.
        public var plan: Plan
    }

    public struct OnDemand: Codable, Equatable, Sendable {
        public var enabled: Bool
        /// Usage-based spend this cycle, in cents.
        public var used: Int
        /// The spend cap in cents, or `nil` when uncapped.
        public var limit: Int?
        public var remaining: Int?
    }

    public struct Plan: Codable, Equatable, Sendable {
        public var enabled: Bool
        /// Included-allowance usage this cycle, in cents.
        public var used: Int
        /// The included allowance in cents.
        public var limit: Int?
        public var remaining: Int?
        public var breakdown: Breakdown?
        /// Percentage (0...100) of the total included allowance used this
        /// cycle, when reported — the figure behind the "N% of included usage"
        /// message.
        public var totalPercentUsed: Double? = nil
        public var autoPercentUsed: Double? = nil
        public var apiPercentUsed: Double? = nil
    }

    public struct Breakdown: Codable, Equatable, Sendable {
        public var included: Int
        public var bonus: Int
        public var total: Int
    }

    public init(
        billingCycleStart: String,
        billingCycleEnd: String,
        membershipType: String,
        individualUsage: IndividualUsage,
    ) {
        self.billingCycleStart = billingCycleStart
        self.billingCycleEnd = billingCycleEnd
        self.membershipType = membershipType
        self.individualUsage = individualUsage
    }

    /// The parsed cycle start, or `nil` if the wire string doesn't parse.
    public var cycleStart: Date? {
        Self.parseDate(billingCycleStart)
    }

    /// The parsed cycle end.
    public var cycleEnd: Date? {
        Self.parseDate(billingCycleEnd)
    }

    /// Usage-based spend this cycle, in cents.
    public var onDemandCents: Int {
        individualUsage.onDemand.used
    }

    /// Fraction (0...1) of the included allowance used this cycle, when the API
    /// reports a percentage.
    public var includedFractionUsed: Double? {
        individualUsage.plan.totalPercentUsed.map { $0 / 100 }
    }

    /// The dashboard's status lines, in order, omitting any the API didn't send.
    public var usageMessages: [String] {
        [autoModelSelectedDisplayMessage, namedModelSelectedDisplayMessage].compactMap(\.self)
    }

    private static func parseDate(_ string: String) -> Date? {
        // Dashboard timestamps carry fractional seconds ("…T18:16:08.000Z").
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
