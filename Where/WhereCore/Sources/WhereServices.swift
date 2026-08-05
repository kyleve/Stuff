import Foundation
import RegionKit

/// The Where feature's service layer: a small `Sendable` container of the
/// focused collaborators that, together, do everything the old `WhereController`
/// god-actor used to. In the app one is assembled per `WhereScope` — the real
/// world's by `WhereBootstrap` when the launch resolves it, a demo world's in
/// memory — and `WhereSession` holds it and talks to the collaborators directly
/// (`await services.journal.…`, `await services.reports.…`).
///
/// The only cross-cutting operation that doesn't belong to a single
/// collaborator is `reset()` (stop GPS, then wipe the store) — it lives here so
/// teardown stays in Core rather than leaking into the UI layer.
public struct WhereServices: Sendable {
    /// Pure reads: `YearReport` + location projections.
    public let reports: ReportReader
    /// Pure reads over user-attached evidence (per-year list, per-day keys for
    /// the calendar badge, attachment bytes). Writes go through `journal`.
    public let evidence: EvidenceReader
    /// Widget snapshot publishing + freshness policy.
    public let widgets: WidgetSnapshotPublisher
    /// Daily logging-reminder intent + badge/schedule reconciliation.
    public let reminders: ReminderReconciler
    /// Daily summary recap intent + reconciliation.
    public let summary: DailySummaryReconciler
    /// "Issues to resolve" notification intent + reconciliation. The
    /// unresolved-issue count it tracks also feeds the app-icon badge via
    /// `reminders`.
    public let issueAlerts: DataIssueAlertReconciler
    /// Live GPS ingestion: monitoring, retry queue, authorization.
    public let ingestor: LocationIngestor
    /// User-sourced writes: manual days, backfills, clears, evidence.
    public let journal: DayJournal
    /// Backup export / import.
    public let backup: BackupCoordinator
    /// The single synced “I’ll be here through…” intent used by location
    /// forecasts.
    public let plannedStays: PlannedStayCoordinator
    /// Data-quality issue detection for the Resolve tab.
    public let resolution: DataIssueScanner
    /// On-device summary of a selectable look-back window of tracked locations
    /// (see `RecentActivityWindow`). Named distinctly from `summary` (the daily
    /// notification recap) — this one is an on-demand Foundation Models
    /// narrative.
    public let recentActivity: RecentActivitySummarizer
    /// The persistence boundary, retained so `dataChangeUpdates()` can hand out
    /// the store's `changes()` stream — the single read-refresh signal every
    /// write origin (manual edit, live GPS, remote sync) funnels through.
    /// Plumbing, so it stays off the public surface.
    let store: any WhereStore
    /// The attribution policy every collaborator was built with (in production
    /// the live tracked-regions `RegionAttribution`). Retained so a derived
    /// stack (`forIntents(sharingStoreOf:)`) shares the *same* attributor
    /// rather than deriving a second live attribution over the same store.
    let attributor: any RegionAttributing
    /// The notification and widget seams the stack was built with, retained so
    /// a derived stack (`forIntents(sharingStoreOf:)`) reconciles through the
    /// *same* ones. Re-minting real ones would let a stack derived from a demo
    /// world — assembled entirely out of no-ops — post a real notification or
    /// reload the user's widgets.
    let reminderScheduler: any LoggingReminderScheduling
    let summaryScheduler: any DailySummaryScheduling
    let issueAlertScheduler: any DataIssueAlertScheduling
    let widgetRefresher: any WidgetTimelineRefreshing
    /// The aggregation policy (calendar + time zone) the stack was built with,
    /// retained so a derived stack buckets days identically.
    let aggregator: DayAggregator
    /// The clock the stack was built with, retained so a derived stack can't
    /// diverge from an injected test/preview clock.
    let now: @Sendable () -> Date
    /// Synchronous assembly with an explicitly-provided `attributor` (default:
    /// the historical four via `RegionAttributor.shared`). For **tests and
    /// previews** — hence `@_spi(Testing)` — which build in-memory stacks without
    /// an async store read. Production wiring (the app launch, the App Intents
    /// process) goes through the public `make(...)`, which derives the attributor
    /// from the store's tracked regions.
    ///
    /// The notification and widget seams default to **no-ops**, because this is
    /// the test/preview seam and the reconcilers behind them fire on ordinary
    /// writes: a suite that named nothing used to schedule real notifications
    /// and reload the user's real widget timelines as a side effect of saving a
    /// day. Production names its own, via `make(...)`.
    @_spi(Testing)
    public init(
        store: any WhereStore,
        locationSource: any LocationSource,
        attributor: any RegionAttributing = RegionAttributor.shared,
        aggregator: DayAggregator = DayAggregator(),
        reminderScheduler: any LoggingReminderScheduling = NoopLoggingReminderScheduler(),
        summaryScheduler: any DailySummaryScheduling = NoopDailySummaryScheduler(),
        issueAlertScheduler: any DataIssueAlertScheduling = NoopDataIssueAlertScheduler(),
        widgetRefresher: any WidgetTimelineRefreshing = NoopWidgetTimelineRefresher(),
        locationOutbox: any LocationOutbox = NoOpLocationOutbox(),
        activitySummaryGenerator: any ActivitySummaryGenerating = FoundationModelSummaryGenerator(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        let reports = ReportReader(store: store, aggregator: aggregator, attributor: attributor)
        let evidence = EvidenceReader(store: store, aggregator: aggregator)
        // Built before the reconcilers that consume it: the reminder reconciler
        // folds its unresolved-issue count into the app-icon badge, and the
        // issue-alert reconciler drives the "issues to resolve" notification off
        // it. Subscribes to `store.changes()` and drops its cache on every commit,
        // so a `force: false` read stays honest even when no session is alive to
        // force a rescan (e.g. a headless background GPS ingest).
        let resolution = DataIssueScanner(
            reportReader: reports,
            attributor: attributor,
            calendar: aggregator.calendar,
            now: now,
            storeChanges: store.changes(),
        )
        let reminders = ReminderReconciler(
            scheduler: reminderScheduler,
            reportReader: reports,
            issueScanner: resolution,
            calendar: aggregator.calendar,
            now: now,
        )
        let summary = DailySummaryReconciler(
            scheduler: summaryScheduler,
            reportReader: reports,
            calendar: aggregator.calendar,
            now: now,
        )
        let issueAlerts = DataIssueAlertReconciler(
            scheduler: issueAlertScheduler,
            scanner: resolution,
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
                    // Hot live-sample path: the reminder reconcile carries the
                    // badge (including its issue count) and self-throttles once
                    // today is covered. The issue-alert notification is less
                    // latency-sensitive and refreshes on the drain/write paths
                    // and every foreground, so it stays off this per-sample path.
                    await reminders.reconcileAfterIngest(changedDays: outcome.changedDays)
                    if outcome.needsFullWidgetRebuild {
                        await widgets.publish()
                    } else {
                        await widgets.publishAfterIngest(of: sample)
                    }
                } else if !outcome.changedDays.isEmpty {
                    await reminders.reconcile()
                    await issueAlerts.reconcile()
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
            issueAlerts: issueAlerts,
            issueScanner: resolution,
            widgets: widgets,
        )
        // An import changes day data, so it reuses the journal's post-day-change
        // reconcile (scanner invalidate + badge/notification reconcile + widget
        // publish) rather than duplicating that fan-out.
        let backup = BackupCoordinator(
            store: store,
            onImport: { await journal.reconcileAfterDayChange() },
        )
        let plannedStays = PlannedStayCoordinator(
            store: store,
            calendar: aggregator.calendar,
            now: now,
        )
        let recentActivity = RecentActivitySummarizer(
            store: store,
            attributor: attributor,
            generator: activitySummaryGenerator,
            calendar: aggregator.calendar,
            now: now,
            segmentLimit: RecentActivitySummarizer.defaultSegmentLimit,
        )

        self.reports = reports
        self.evidence = evidence
        self.reminders = reminders
        self.summary = summary
        self.issueAlerts = issueAlerts
        self.widgets = widgets
        self.ingestor = ingestor
        self.journal = journal
        self.backup = backup
        self.plannedStays = plannedStays
        self.resolution = resolution
        self.recentActivity = recentActivity
        self.store = store
        self.attributor = attributor
        self.aggregator = aggregator
        self.reminderScheduler = reminderScheduler
        self.summaryScheduler = summaryScheduler
        self.issueAlertScheduler = issueAlertScheduler
        self.widgetRefresher = widgetRefresher
        self.now = now
    }

    /// Assemble services whose attributor is derived from the store's **tracked
    /// regions** (the synced set the user chose, or the default four) and stays
    /// live: the returned `RegionAttribution` rebuilds on `store.changes()` when
    /// that set changes — a local edit or a remote CloudKit import.
    ///
    /// Reading the tracked set is why this is `async` where `init` is not: the
    /// synchronous `init` is for tests/previews (in-memory stores with no tracked
    /// rows resolve to the default four, matching `RegionAttributor.shared`),
    /// while production wiring — the app launch and the App Intents process —
    /// goes through here so both attribute against the *same* stored set.
    public static func make(
        store: any WhereStore,
        locationSource: any LocationSource,
        aggregator: DayAggregator = DayAggregator(),
        reminderScheduler: any LoggingReminderScheduling,
        summaryScheduler: any DailySummaryScheduling,
        issueAlertScheduler: any DataIssueAlertScheduling,
        widgetRefresher: any WidgetTimelineRefreshing,
        locationOutbox: any LocationOutbox = NoOpLocationOutbox(),
        activitySummaryGenerator: any ActivitySummaryGenerating = FoundationModelSummaryGenerator(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) async throws -> WhereServices {
        let tracked = try await store.trackedRegions()
        let attribution = RegionAttribution(
            store: store,
            // Canonical order (not `Array(Set)`) so the attributor's first-match
            // priority is deterministic and matches the catalog order.
            initial: RegionAttributor(for: Region.inCanonicalOrder(tracked)),
            trackedIDs: Set(tracked.map(\.rawValue)),
        )
        return WhereServices(
            store: store,
            locationSource: locationSource,
            attributor: attribution,
            aggregator: aggregator,
            reminderScheduler: reminderScheduler,
            summaryScheduler: summaryScheduler,
            issueAlertScheduler: issueAlertScheduler,
            widgetRefresher: widgetRefresher,
            locationOutbox: locationOutbox,
            activitySummaryGenerator: activitySummaryGenerator,
            now: now,
        )
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

    /// The user's tracked regions (the synced set the app attributes against),
    /// read fresh from the store. Exposed for the App Intents layer, whose "pick
    /// a region" suggestions and Spotlight index surface the tracked set (rather
    /// than every available region).
    public func trackedRegions() async throws -> Set<Region> {
        try await store.trackedRegions()
    }

    /// The user's primary (tracked) regions with their picked appearance and
    /// order — the store's ``PrimaryRegion`` rows. Drives the region picker /
    /// customization UI and seeds the presentation layer's region styling.
    public func primaryRegions() async throws -> [PrimaryRegion] {
        try await store.primaryRegions()
    }

    /// Replace the user's primary (tracked) regions with `regions` — the
    /// picker/customization commit path. One `perform`, so the whole change
    /// (upserts + removals-by-omission) is a single atomic transaction that
    /// pings `changes()` once.
    public func setPrimaryRegions(_ regions: [PrimaryRegion]) async throws {
        try await store.perform {
            try await store.setPrimaryRegions(regions)
        }
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
        // `eraseAllData()` commits, which pings `store.changes()` and the
        // scanner self-invalidates off it — but that observation is async. Drop
        // the cache inline too so it's provably empty by the time `reset()`
        // returns rather than racing the observer; this is the deterministic
        // half of that pair, not redundant with it.
        await resolution.invalidate()
    }
}
