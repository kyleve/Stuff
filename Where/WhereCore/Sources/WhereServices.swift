import Foundation

/// The Where feature's service layer: a small `Sendable` container of the
/// focused collaborators that, together, do everything the old `WhereController`
/// god-actor used to. `WhereBootstrap` assembles one in the launch's
/// `open-store` step; `WhereSession` (and, transitionally, `WhereModel`) holds
/// it and talks to the collaborators directly (`await services.journal.…`,
/// `await services.reports.…`).
///
/// The only cross-cutting operation that doesn't belong to a single
/// collaborator is `reset()` (stop GPS, then wipe the store) — it lives here so
/// teardown stays in Core rather than leaking into the UI layer.
public struct WhereServices: Sendable {
    /// Pure reads: `YearReport` + location projections.
    public let reports: ReportReader
    /// Widget snapshot publishing + freshness policy.
    public let widgets: WidgetSnapshotPublisher
    /// Daily logging-reminder intent + badge/schedule reconciliation.
    public let reminders: ReminderReconciler
    /// Daily summary recap intent + reconciliation.
    public let summary: DailySummaryReconciler
    /// Live GPS ingestion: monitoring, retry queue, authorization.
    public let ingestor: LocationIngestor
    /// User-sourced writes: manual days, backfills, clears, evidence.
    public let journal: DayJournal
    /// Backup export / import.
    public let backup: BackupCoordinator

    public init(
        store: any WhereStore,
        locationSource: any LocationSource,
        attributor: RegionAttributor = .shared,
        aggregator: DayAggregator = DayAggregator(),
        reminderScheduler: any LoggingReminderScheduling = UserNotificationReminderScheduler(),
        summaryScheduler: any DailySummaryScheduling = UserNotificationDailySummaryScheduler(),
        widgetRefresher: any WidgetTimelineRefreshing = WidgetCenterTimelineRefresher(),
        locationOutbox: any LocationOutbox = NoOpLocationOutbox(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        let reports = ReportReader(store: store, aggregator: aggregator, attributor: attributor)
        let reminders = ReminderReconciler(
            scheduler: reminderScheduler,
            reportReader: reports,
            calendar: aggregator.calendar,
            now: now,
        )
        let summary = DailySummaryReconciler(
            scheduler: summaryScheduler,
            reportReader: reports,
            calendar: aggregator.calendar,
            now: now,
        )
        // The reader runs in *this* (app) process and shares the store, calendar,
        // and attributor so the published snapshot's day/year line up with
        // everything else reported.
        let widgetReader = WidgetDataReader(
            store: store,
            aggregator: aggregator,
            attributor: attributor,
        )
        let widgets = WidgetSnapshotPublisher(
            widgetReader: widgetReader,
            widgetRefresher: widgetRefresher,
            attributor: attributor,
            calendar: aggregator.calendar,
            now: now,
        )
        // After each committed GPS persist, reconcile the badge/reminders and
        // republish the widget snapshot. A live single sample uses the cheap
        // change-detection unless a drain also re-persisted other days; a
        // resume/drain-only batch reconciles fully and publishes only if it
        // actually persisted anything.
        let ingestor = LocationIngestor(
            store: store,
            locationSource: locationSource,
            calendar: aggregator.calendar,
            outbox: locationOutbox,
            onPersisted: { outcome in
                if let sample = outcome.liveSample {
                    await reminders.reconcileAfterIngest(changedDays: outcome.changedDays)
                    if outcome.needsFullWidgetRebuild {
                        await widgets.publish()
                    } else {
                        await widgets.publishAfterIngest(of: sample)
                    }
                } else {
                    await reminders.reconcile()
                    if outcome.needsFullWidgetRebuild {
                        await widgets.publish()
                    }
                }
            },
        )
        let journal = DayJournal(
            store: store,
            aggregator: aggregator,
            reminders: reminders,
            widgets: widgets,
        )
        let backup = BackupCoordinator(store: store, widgets: widgets)

        self.reports = reports
        self.reminders = reminders
        self.summary = summary
        self.widgets = widgets
        self.ingestor = ingestor
        self.journal = journal
        self.backup = backup
    }

    /// Return the services to a clean slate for the app's "erase all data &
    /// reset" teardown: quiesce GPS ingestion (stop monitoring, refuse further
    /// samples, await any in-flight write, and drop the retry backlog) so
    /// nothing can write into the store as it's wiped, then erase everything
    /// (which also reconciles the badge/reminders and republishes an empty
    /// widget snapshot).
    ///
    /// This is the one inherently cross-collaborator operation; keeping it here
    /// keeps teardown ordering in Core rather than the UI. Quiescing before the
    /// wipe is what makes the erase stick: a plain `stop()` would leave the
    /// ingestion loop and its retry queue able to repopulate the store. Throws
    /// on persistence failure so the caller can surface it rather than silently
    /// half-erasing.
    public func reset() async throws {
        await ingestor.quiesce()
        try await journal.eraseAllData()
    }
}
