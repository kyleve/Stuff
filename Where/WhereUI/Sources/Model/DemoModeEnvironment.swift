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

extension View {
    /// Seed `\.isInDemoMode` from which world `model` is logged in to.
    ///
    /// A named modifier rather than an inline `environment(_:_:)` at the app
    /// root, so the mapping from scope state to environment is one thing with a
    /// test on it (`DemoModeEnvironmentTests`) instead of an expression that
    /// could quietly be deleted, taking the way out of demo mode with it.
    public func demoMode(of model: WhereModel) -> some View {
        environment(\.isInDemoMode, model.isInDemoMode)
    }
}
