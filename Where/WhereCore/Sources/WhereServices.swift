import Foundation
import SwiftData

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
    /// Data-quality issue detection for the Resolve tab.
    public let resolution: DataIssueScanner
    /// The persistence boundary, retained so `dataChangeUpdates()` can hand out
    /// the store's `changes()` stream — the single read-refresh signal every
    /// write origin (manual edit, live GPS, remote sync) funnels through.
    /// Plumbing, so it stays off the public surface.
    let store: any WhereStore
    /// The live SwiftData container when the backing store is the production
    /// `SwiftDataStore`; `nil` for non-SwiftData stores (e.g. test fakes).
    /// Surfaced only for read-only debug tooling (the SwiftData inspector) so
    /// SwiftData never has to route through the value-type `WhereStore` boundary.
    public let modelContainer: ModelContainer?

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
                } else if !outcome.changedDays.isEmpty {
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
        // Subscribes to `store.changes()` and drops its cache on every commit,
        // so a `force: false` read stays honest even when no session is alive to
        // force a rescan (e.g. a headless background GPS ingest).
        let resolution = DataIssueScanner(
            reportReader: reports,
            attributor: attributor,
            calendar: aggregator.calendar,
            now: now,
            storeChanges: store.changes(),
        )

        self.reports = reports
        self.reminders = reminders
        self.summary = summary
        self.widgets = widgets
        self.ingestor = ingestor
        self.journal = journal
        self.backup = backup
        self.resolution = resolution
        self.store = store
        modelContainer = (store as? SwiftDataStore)?.inspectorContainer
    }

    /// A fresh stream that fires whenever persisted data changes — local commits
    /// (manual edits, live GPS ingestion) and, for a CloudKit-backed store,
    /// remote imports synced from another device. `WhereSession` subscribes and
    /// re-pulls its report + data-issue scan, so the UI it mirrors can't go stale
    /// behind a write it didn't initiate. Each subscriber gets an isolated stream
    /// (see `StoreChangeBroadcaster`).
    public func dataChangeUpdates() -> AsyncStream<Void> {
        store.changes()
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
        await resolution.invalidate()
    }
}
