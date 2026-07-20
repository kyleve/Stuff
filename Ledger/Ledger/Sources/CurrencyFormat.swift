import Foundation

/// USD formatting for spend figures.
enum CurrencyFormat {
    /// A full currency string, e.g. `$1,234.56` — used in the popover.
    static func dollars(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD"))
    }

    /// A compact, glanceable amount for the menu bar: no cents, rounded to the
    /// nearest dollar under $100 and to the nearest $10 at $100 and above
    /// (e.g. `$12`, `$3,240`).
    static func menuBar(_ dollars: Double) -> String {
        let increment: Double = abs(dollars) >= 100 ? 10 : 1
        let rounded = (dollars / increment).rounded() * increment
        return rounded.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
