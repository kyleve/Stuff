import Foundation

/// USD formatting for spend figures. One place so the menu-bar title and the
/// popover render dollars identically.
enum CurrencyFormat {
    /// A full currency string, e.g. `$1,234.56`.
    static func full(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD"))
    }

    /// The menu-bar title form — the same currency string; kept as its own
    /// entry point so the status-item presentation can diverge later without
    /// touching call sites.
    static func compact(_ dollars: Double) -> String {
        full(dollars)
    }
}
