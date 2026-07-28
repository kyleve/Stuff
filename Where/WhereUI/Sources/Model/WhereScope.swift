import Foundation
import WhereCore

/// Everything the app is logged in *to*: the service layer over one open
/// store, and the preferences whose intent that layer is driven by.
///
/// A scope is created whole and never reconfigured — the store it carries is
/// opened once, and swapping what the app is logged in to means activating a
/// *different* scope rather than reassigning fields on this one. `WhereModel`
/// owns which scope is active; `WhereSession` is built from one, so every
/// logged-in surface reads the store and the preferences of the same scope
/// and the two can't drift apart.
///
/// The split it draws is app-scope versus logged-in scope: `WhereModel` lives
/// for the process (it exists before any store is open, and outlives a reset),
/// while everything here belongs to one logged-in world.
@MainActor
public final class WhereScope {
    /// The service layer — the entry point to the domain for every logged-in
    /// surface. Owns this scope's store.
    let services: WhereServices

    /// The persisted user intent (onboarding, tracking, reminder/summary
    /// schedules) this scope reads and writes. A reference, shared with
    /// whoever else holds these preferences, so a write from onboarding and a
    /// read from the session see one store.
    let preferences: WherePreferences

    /// Build a scope over an already-assembled service layer. The app builds
    /// its scope in the launch's `open-store` step; this is also the seam
    /// previews and tests inject one through.
    public init(services: WhereServices, preferences: WherePreferences) {
        self.services = services
        self.preferences = preferences
    }
}
