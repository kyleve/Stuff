import Foundation

extension WhereServices {
    /// Assemble a read/write service stack for the App Intents layer (Siri,
    /// Spotlight, Shortcuts) running outside the main app UI.
    ///
    /// Opens the shared App Group SwiftData store in `.localOnly` mode — exactly
    /// like the share extension — so an intent sees the same on-disk data the app
    /// persists (CloudKit mirrors into that same local store) without this
    /// short-lived process spinning up its own CloudKit stack. It wires
    /// ``IdleLocationSource`` so resolving an intent never starts GPS. Reads go
    /// through `reports` / `recentActivity`; user-asserted writes through
    /// `journal`, whose commit the running app observes via
    /// `.NSPersistentStoreRemoteChange` (the single read-refresh signal).
    ///
    /// Throws if the store can't be opened (e.g. the App Group container is
    /// unavailable) so the intent surfaces an honest failure rather than acting
    /// on an empty store.
    public static func forIntents(
        now: @escaping @Sendable () -> Date = { Date() },
    ) throws -> WhereServices {
        try makeForIntents(store: SwiftDataStore.make(storage: .localOnly), now: now)
    }

    /// Composition seam shared by `forIntents()` (production, real App Group
    /// store) and unit tests (an in-memory store): wraps `store` in the same
    /// GPS-free service stack an intent uses.
    static func makeForIntents(
        store: any WhereStore,
        now: @escaping @Sendable () -> Date = { Date() },
    ) -> WhereServices {
        WhereServices(store: store, locationSource: IdleLocationSource(), now: now)
    }
}
