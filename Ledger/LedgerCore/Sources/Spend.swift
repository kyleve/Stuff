import Foundation

/// The decoded response of `POST /teams/spend` (Cursor Admin API).
///
/// Only the fields Ledger reads are modeled; the endpoint returns more
/// (pagination, totals) that synthesized `Codable` simply ignores. Unknown or
/// team-tier-specific fields being absent is expected, not an error.
public struct SpendResponse: Codable, Equatable, Sendable {
    /// Per-member spend for the current billing cycle.
    public var teamMemberSpend: [MemberSpend]

    /// Start of the current billing cycle, as milliseconds since the Unix
    /// epoch, when the API includes it. Surfaced so the UI can label the cycle.
    public var subscriptionCycleStart: Double?

    public init(teamMemberSpend: [MemberSpend], subscriptionCycleStart: Double? = nil) {
        self.teamMemberSpend = teamMemberSpend
        self.subscriptionCycleStart = subscriptionCycleStart
    }

    /// The member whose email matches `email`, case-insensitively — the caller
    /// (Ledger) filters the whole team down to the signed-in user. `nil` when
    /// no member matches (surfaced as ``LedgerServices/LoadError/memberNotFound``).
    public func member(matching email: String) -> MemberSpend? {
        let target = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
        return teamMemberSpend.first { $0.email.lowercased() == target }
    }
}

/// One team member's current-cycle spend.
///
/// Cent fields are `Double` on purpose: on 2026-06-04 the Admin API added
/// sub-cent precision to `spendCents`/`overallSpendCents` so results reconcile
/// with invoice amounts, so these are not whole integers.
public struct MemberSpend: Codable, Equatable, Sendable, Identifiable {
    public var userId: String
    public var name: String?
    public var email: String
    /// On-demand (overage) spend in cents for the current cycle — excludes
    /// included usage.
    public var spendCents: Double
    /// Spend drawn from the member's included usage allowance, in cents, when
    /// the API reports it (tiered self-serve teams).
    public var includedSpendCents: Double?
    /// Total cycle-to-date spend in cents (on-demand + included) when the API
    /// reports it. May be absent depending on team type.
    public var overallSpendCents: Double?
    /// Number of usage-based premium requests made during the cycle.
    public var fastPremiumRequests: Int?

    public var id: String {
        userId
    }

    public init(
        userId: String,
        name: String?,
        email: String,
        spendCents: Double,
        includedSpendCents: Double?,
        overallSpendCents: Double?,
        fastPremiumRequests: Int?,
    ) {
        self.userId = userId
        self.name = name
        self.email = email
        self.spendCents = spendCents
        self.includedSpendCents = includedSpendCents
        self.overallSpendCents = overallSpendCents
        self.fastPremiumRequests = fastPremiumRequests
    }

    /// Total cycle-to-date spend in cents. Prefers the API's own
    /// `overallSpendCents`; when that's absent (some team types omit it) it
    /// falls back to on-demand + included so the headline figure is never
    /// silently short.
    public var totalCents: Double {
        overallSpendCents ?? (spendCents + (includedSpendCents ?? 0))
    }

    /// Total cycle-to-date spend in dollars.
    public var totalDollars: Double {
        totalCents / 100
    }

    /// On-demand (overage) spend in dollars.
    public var onDemandDollars: Double {
        spendCents / 100
    }

    /// Included-allowance spend in dollars, or `nil` when the API omits it.
    public var includedDollars: Double? {
        includedSpendCents.map { $0 / 100 }
    }
}
