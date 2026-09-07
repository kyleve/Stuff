import Foundation

/// One decoded row of `POST /api/dashboard/get-filtered-usage-events` — a
/// single usage event with its model and real charged cost. Only the fields
/// Ledger aggregates are modeled; the endpoint returns many more.
public struct UsageEvent: Codable, Equatable, Sendable {
    public var model: String
    /// The event's charged cost in cents (the endpoint reports it as a number,
    /// sometimes fractional). Absent/negative reads as 0.
    public var chargedCents: Double?

    public init(model: String, chargedCents: Double?) {
        self.model = model
        self.chargedCents = chargedCents
    }

    /// The event's cost in cents, floored at 0.
    public var cents: Double {
        max(0, chargedCents ?? 0)
    }
}

/// A page of the `get-filtered-usage-events` response.
public struct UsageEventsPage: Codable, Equatable, Sendable {
    public var usageEventsDisplay: [UsageEvent]
    public var totalUsageEventsCount: Int

    public init(usageEventsDisplay: [UsageEvent], totalUsageEventsCount: Int) {
        self.usageEventsDisplay = usageEventsDisplay
        self.totalUsageEventsCount = totalUsageEventsCount
    }
}

/// One model's relative share of usage this cycle (0...1). Deliberately
/// dollar-free: the events' summed cost is *total usage value* (included
/// allowance + on-demand), which is more than the billed on-demand headline,
/// so showing it as spend alongside the headline would mislead.
public struct ModelShare: Equatable, Sendable, Identifiable {
    public var name: String
    public var fraction: Double

    public var id: String {
        name
    }

    public init(name: String, fraction: Double) {
        self.name = name
        self.fraction = fraction
    }

    /// Aggregates events into per-model shares of the total charged cost,
    /// highest first (ties broken by name for a stable order).
    public static func shares(from events: [UsageEvent]) -> [ModelShare] {
        var totals: [String: Double] = [:]
        for event in events where event.cents > 0 {
            totals[event.model, default: 0] += event.cents
        }
        let total = totals.values.reduce(0, +)
        guard total > 0 else { return [] }
        return totals
            .map { ModelShare(name: $0.key, fraction: $0.value / total) }
            .sorted {
                $0.fraction > $1.fraction || ($0.fraction == $1.fraction && $0.name < $1.name)
            }
    }
}
