import Foundation

/// USD formatting for spend figures. One place so the menu-bar title and the
/// popover render dollars identically.
enum CurrencyFormat {
    /// A full currency string, e.g. `$1,234.56`.
    static func dollars(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD"))
    }
}
