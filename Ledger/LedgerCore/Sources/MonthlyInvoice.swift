import Foundation

/// The decoded `POST /api/dashboard/get-monthly-invoice` response for one
/// month. Completed months carry itemized `cents` lines; the in-progress month
/// can come back with no `items` until charges post — modeled as an optional
/// so "not yet billed" reads as an empty total, not a decode failure.
public struct MonthlyInvoice: Codable, Equatable, Sendable {
    public var items: [Item]?

    public struct Item: Codable, Equatable, Sendable {
        /// Human-readable line (model, call count, dollar total).
        public var description: String
        /// The line's charge, in cents.
        public var cents: Int

        public init(description: String, cents: Int) {
            self.description = description
            self.cents = cents
        }
    }

    public init(items: [Item]?) {
        self.items = items
    }

    /// The month's total charge in cents (0 when nothing is billed yet).
    public var totalCents: Int {
        (items ?? []).reduce(0) { $0 + $1.cents }
    }
}
