import Foundation

/// The spend figures Ledger renders, distilled from the usage summary and the
/// per-model aggregation into one value the UI binds to. All money is cents.
public struct SpendSnapshot: Equatable, Sendable {
    /// Usage-based spend for the current billing cycle (live, from the usage
    /// summary).
    public var currentCycleCents: Int
    /// Today's and this-week's spend, derived from local history (each `nil`
    /// until enough history exists).
    public var deltas: SpendDeltas
    /// The current billing cycle's start/end, when known.
    public var cycleStart: Date?
    public var cycleEnd: Date?
    /// Plan tier (`"pro"`, `"ultra"`, …).
    public var membershipType: String
    /// Fraction (0...1) of the included first-party/Auto allowance used this
    /// cycle, when known.
    public var autoFractionUsed: Double?
    /// Fraction (0...1) of the included third-party/API allowance used this
    /// cycle, when known.
    public var apiFractionUsed: Double?
    /// Models by usage this cycle, as relative shares highest-first (dollar-free
    /// — see ``AggregatedUsage``). Empty when the per-model fetch is unavailable.
    public var modelShares: [ModelShare]

    public init(
        currentCycleCents: Int,
        deltas: SpendDeltas,
        cycleStart: Date?,
        cycleEnd: Date?,
        membershipType: String,
        autoFractionUsed: Double?,
        apiFractionUsed: Double?,
        modelShares: [ModelShare],
    ) {
        self.currentCycleCents = currentCycleCents
        self.deltas = deltas
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.membershipType = membershipType
        self.autoFractionUsed = autoFractionUsed
        self.apiFractionUsed = apiFractionUsed
        self.modelShares = modelShares
    }

    public var currentCycleDollars: Double {
        Double(currentCycleCents) / 100
    }
}
