import Foundation

extension WhereServices {
    /// Assemble the App Intents stack (Siri, Spotlight, Shortcuts — executing
    /// in the app's own process) over the **same store `base` already holds**,
    /// so an intent never opens a second container over the store file the
    /// app has open — and an intent write pings the same `changes()` signal
    /// the running UI refreshes from.
    ///
    /// This is the injection seam the app's composition root uses: after the
    /// launch assembles its services, it derives the intents stack from them
    /// and installs it into the intent layer's cache (see `IntentServices` in
    /// WhereIntents). Only the *store* is shared — the stack wires
    /// ``IdleLocationSource``, so resolving an intent never starts GPS.
    public static func forIntents(
        sharingStoreOf base: WhereServices,
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        try await makeForIntents(store: base.store, now: now)
    }

    /// Assemble a self-contained read/write service stack for the App Intents
    /// layer — the **fallback** for an intent that fires before the app's
    /// launch has installed the store-sharing stack built by
    /// `forIntents(sharingStoreOf:now:)` (e.g. a Siri invocation launching the
    /// process, racing ahead of the `open-store` step).
    ///
    /// Opens the shared App Group SwiftData store in `.localOnly` mode — like
    /// the share extension — so the intent sees the same on-disk data the app
    /// persists without spinning up its own CloudKit stack for a short-lived
    /// invocation. It wires ``IdleLocationSource`` so resolving an intent
    /// never starts GPS. Reads go through `reports` / `recentActivity`;
    /// user-asserted writes through `journal`, whose commit the running app
    /// observes via `.NSPersistentStoreRemoteChange`.
    ///
    /// Throws if the store can't be opened (e.g. the App Group container is
    /// unavailable) so the intent surfaces an honest failure rather than acting
    /// on an empty store.
    public static func forIntents(
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        try await makeForIntents(store: SwiftDataStore.make(storage: .localOnly), now: now)
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
