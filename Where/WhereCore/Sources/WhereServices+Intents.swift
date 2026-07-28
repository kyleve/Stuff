import Foundation

extension WhereServices {
    /// Assemble the App Intents stack (Siri, Spotlight, Shortcuts — executing
    /// in the app's own process) over the **same store, live attribution,
    /// aggregation calendar, and clock `base` already holds** — only the
    /// location source differs (``IdleLocationSource``, so resolving an
    /// intent never starts GPS).
    ///
    /// This is the *only* way an intents stack is built, and it is
    /// deliberately synchronous and non-throwing: deriving from an assembled
    /// service layer opens nothing and re-reads nothing, so the composition
    /// hook that installs it (`WhereLaunch.makeLauncher`'s `onServicesReady`
    /// → `IntentServices` in WhereIntents) has no failure path that could
    /// strand parked intents behind a logged-and-dropped error. The launch's
    /// `resolve-scope` step stays the process's one store open, an intent can
    /// never race it with a second container over the same file, and an
    /// intent write pings the same `changes()` signal the running UI
    /// refreshes from.
    ///
    /// The notification and widget seams come from `base` for the same reason
    /// the attributor does: a stack derived from the demo world is built out of
    /// no-ops, and minting real ones here would let a demo intent post a real
    /// notification or reload the user's widgets.
    public static func forIntents(sharingStoreOf base: WhereServices) -> WhereServices {
        WhereServices(
            store: base.store,
            locationSource: IdleLocationSource(),
            attributor: base.attributor,
            aggregator: base.aggregator,
            reminderScheduler: base.reminderScheduler,
            summaryScheduler: base.summaryScheduler,
            issueAlertScheduler: base.issueAlertScheduler,
            widgetRefresher: base.widgetRefresher,
            now: base.now,
        )
    }

    /// Test seam: wraps an in-memory `store` in the same GPS-free service
    /// stack an intent uses. Unlike the production
    /// `forIntents(sharingStoreOf:)` — which shares an assembled layer's
    /// attributor — this derives one from the store's tracked regions (via
    /// ``make(store:locationSource:)``, hence `async throws`), so a test can
    /// seed tracked rows and observe the derived attribution.
    static func makeForIntents(
        store: any WhereStore,
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        try await make(
            store: store,
            locationSource: IdleLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: now,
        )
    }
}
