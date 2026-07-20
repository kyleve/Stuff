import Foundation

/// The spend figures Ledger renders, distilled from the usage summary and the
/// per-model aggregation into one value the UI binds to. All money is cents.
public struct SpendSnapshot: Equatable, Sendable {
    /// Usage-based spend for the current billing cycle (live, from the usage
    /// summary).
    public var currentCycleCents: Int
    /// The current billing cycle's start/end, when known.
    public var cycleStart: Date?
    public var cycleEnd: Date?
    /// Plan tier (`"pro"`, `"ultra"`, …).
    public var membershipType: String
    /// Fraction (0...1) of the included allowance used this cycle, when known.
    public var includedFractionUsed: Double?
    /// Models by usage this cycle, as relative shares highest-first (dollar-free
    /// — see ``AggregatedUsage``). Empty when the per-model fetch is unavailable.
    public var modelShares: [ModelShare]

    public init(
        currentCycleCents: Int,
        cycleStart: Date?,
        cycleEnd: Date?,
        membershipType: String,
        includedFractionUsed: Double?,
        modelShares: [ModelShare],
    ) {
        self.currentCycleCents = currentCycleCents
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.membershipType = membershipType
        self.includedFractionUsed = includedFractionUsed
        self.modelShares = modelShares
    }

    public var currentCycleDollars: Double {
        Double(currentCycleCents) / 100
    }
}
