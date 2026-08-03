import Foundation

extension WhereServices {
    /// Hand App Intents (Siri, Spotlight, Shortcuts — executing in the app's own process) the
    /// exact assembled stack the app already owns.
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
    /// Sharing the value also shares its actor references, especially the one
    /// `DeviceRecordingController` that owns this installation's check-in. Rebuilding a nominally
    /// GPS-free stack would create a second controller capable of acknowledging `.recording`
    /// through an idle source and racing the app's real authority.
    public static func forIntents(sharingStoreOf base: WhereServices) -> WhereServices {
        base
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
            installationContext: .testing,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            importRecoveryPersistence: .none,
            now: now,
        )
    }
}
