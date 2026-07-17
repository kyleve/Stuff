import Foundation

extension WhereServices {
    /// Assemble a read/write service stack for the App Intents layer (Siri,
    /// Spotlight, Shortcuts), which executes in the app's own process.
    ///
    /// Resolves the process's **canonical** store (`SwiftDataStore.canonical()`)
    /// — the same instance the launch's `open-store` step uses — rather than
    /// opening a second container over the same store file. That shares one
    /// container per process (an intent write pings the same `changes()` signal
    /// the UI refreshes from) and, on a fresh install, removes the race where
    /// two containers both tried to *create* the store file and one threw. It
    /// wires ``IdleLocationSource`` so resolving an intent never starts GPS.
    /// Reads go through `reports` / `recentActivity`; user-asserted writes
    /// through `journal`.
    ///
    /// Throws if the store can't be opened (e.g. the App Group container is
    /// unavailable) so the intent surfaces an honest failure rather than acting
    /// on an empty store.
    public static func forIntents(
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        try await makeForIntents(store: SwiftDataStore.canonical(), now: now)
    }

    /// Composition seam shared by `forIntents()` (production, real App Group
    /// store) and unit tests (an in-memory store): wraps `store` in the same
    /// GPS-free service stack an intent uses. `async` because it derives the
    /// attributor from the store's tracked regions (via ``make(store:locationSource:)``),
    /// so an intent attributes against the same synced set the app does.
    static func makeForIntents(
        store: any WhereStore,
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        try await make(store: store, locationSource: IdleLocationSource(), now: now)
    }
}
