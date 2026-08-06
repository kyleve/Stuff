import Foundation

/// USD formatting for spend figures.
enum CurrencyFormat {
    /// A full currency string, e.g. `$1,234.56` — used in the popover.
    static func dollars(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD"))
    }

    /// A glanceable amount for the menu bar: the popover figure with the cents
    /// dropped (truncated, so it never reads higher than the real amount and
    /// shares its visible digits — `$3,662.77` → `$3,662`).
    static func menuBar(_ dollars: Double) -> String {
        dollars.rounded(.down).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
