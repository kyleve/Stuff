import Foundation

/// The spend figures Ledger renders, distilled from the usage summary and the
/// year's monthly invoices into one value the UI binds to. All money is cents.
public struct SpendSnapshot: Equatable, Sendable {
    /// Usage-based spend for the current billing cycle (live, from the usage
    /// summary).
    public var currentCycleCents: Int
    /// Usage-based spend billed so far this calendar year (sum of the monthly
    /// invoices).
    public var yearToDateCents: Int
    /// The current billing cycle's start/end, when known.
    public var cycleStart: Date?
    public var cycleEnd: Date?
    /// Plan tier (`"pro"`, `"ultra"`, …).
    public var membershipType: String
    /// Included-allowance usage this cycle, in cents (when reported).
    public var includedUsedCents: Int?
    /// The included allowance in cents (when reported).
    public var includedLimitCents: Int?

    public init(
        currentCycleCents: Int,
        yearToDateCents: Int,
        cycleStart: Date?,
        cycleEnd: Date?,
        membershipType: String,
        includedUsedCents: Int?,
        includedLimitCents: Int?,
    ) {
        self.currentCycleCents = currentCycleCents
        self.yearToDateCents = yearToDateCents
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.membershipType = membershipType
        self.includedUsedCents = includedUsedCents
        self.includedLimitCents = includedLimitCents
    }

    public var currentCycleDollars: Double {
        Double(currentCycleCents) / 100
    }

    public var yearToDateDollars: Double {
        Double(yearToDateCents) / 100
    }

    public var includedUsedDollars: Double? {
        includedUsedCents.map { Double($0) / 100 }
    }

    public var includedLimitDollars: Double? {
        includedLimitCents.map { Double($0) / 100 }
    }
}
