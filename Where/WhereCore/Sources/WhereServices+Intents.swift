import Foundation

extension WhereServices {
    /// Assemble the App Intents stack (Siri, Spotlight, Shortcuts — executing
    /// in the app's own process) over the **same store `base` already holds**.
    ///
    /// This is the *only* way an intents stack is built, and it never opens a
    /// store: the app's composition root derives it from the launch's services
    /// and installs it into the intent layer's handoff (see `IntentServices`
    /// in WhereIntents, wired through `WhereLaunch.makeLauncher`'s
    /// `onServicesReady` hook) — so the launch's `open-store` step is the
    /// process's one store open, an intent can never race it with a second
    /// container over the same file, and an intent write pings the same
    /// `changes()` signal the running UI refreshes from. Only the *store* is
    /// shared — the stack wires ``IdleLocationSource``, so resolving an
    /// intent never starts GPS.
    public static func forIntents(
        sharingStoreOf base: WhereServices,
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        try await makeForIntents(store: base.store, now: now)
    }

    /// Composition seam shared by `forIntents(sharingStoreOf:)` (production,
    /// the launch's store) and unit tests (an in-memory store): wraps `store`
    /// in the same GPS-free service stack an intent uses. `async` because it
    /// derives the attributor from the store's tracked regions (via
    /// ``make(store:locationSource:)``), so an intent attributes against the
    /// same synced set the app does.
    static func makeForIntents(
        store: any WhereStore,
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        try await make(store: store, locationSource: IdleLocationSource(), now: now)
    }
}
