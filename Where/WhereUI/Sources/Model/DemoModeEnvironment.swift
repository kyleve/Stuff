import SwiftUI

extension EnvironmentValues {
    /// Whether the app is running on demo data rather than the user's own.
    ///
    /// Seeded once at the app root from `WhereModel`'s scope state (see
    /// `RootView`) and read by the few surfaces that must behave differently:
    /// Settings shows the way out, and the rows that would write something the
    /// device keeps — a backup, an erase, an alternate app icon — step aside,
    /// since a demo must leave no mark.
    ///
    /// Defaults to `false`, so a view rendered outside the app root (a preview,
    /// a widget) reads as the real app, which is the safer answer: the cost of
    /// wrongly believing you're in demo mode is hiding real controls.
    @Entry public var isInDemoMode: Bool = false
}
