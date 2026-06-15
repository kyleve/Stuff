import Foundation

/// Top-level API for the Where feature. Composes a `WhereStore`
/// (persistence) with focused collaborators — a `LocationIngestor` (GPS), a
/// `WidgetSnapshotPublisher`, the reminder / daily-summary reconcilers, a
/// `DayJournal` (user-sourced writes), and a `BackupCoordinator` (export /
/// import) — behind a small, testable surface.
///
/// - GPS sampling is opt-in: callers invoke `startGPS()` once the user grants
///   authorization; the `LocationIngestor` owns the monitoring lifecycle and
///   stream.
/// - Retroactive entry uses `addManualSample(_:)` (a single coordinate) or
///   `addManualDay(date:regions:)` (an authoritative day overlay that unions
///   with whatever GPS produced for that day).
/// - `yearReport(for:)` reads everything in the requested calendar year via
///   the injected `DayAggregator` and returns a snapshot-stable `YearReport`.
public actor WhereController {
    private let reportReader: ReportReader
    private let reminderReconciler: ReminderReconciler
    private let summaryReconciler: DailySummaryReconciler
    private let widgetPublisher: WidgetSnapshotPublisher
    private let locationIngestor: LocationIngestor
    private let journal: DayJournal
    private let backupCoordinator: BackupCoordinator

    public init(
        store: any WhereStore,
        locationSource: any LocationSource,
        attributor: RegionAttributor = .shared,
        aggregator: DayAggregator = DayAggregator(),
        reminderScheduler: any LoggingReminderScheduling = UserNotificationReminderScheduler(),
        summaryScheduler: any DailySummaryScheduling = UserNotificationDailySummaryScheduler(),
        widgetRefresher: any WidgetTimelineRefreshing = WidgetCenterTimelineRefresher(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        reportReader = ReportReader(store: store, aggregator: aggregator, attributor: attributor)
        let reminders = ReminderReconciler(
            scheduler: reminderScheduler,
            reportReader: reportReader,
            calendar: aggregator.calendar,
            now: now,
        )
        reminderReconciler = reminders
        summaryReconciler = DailySummaryReconciler(
            scheduler: summaryScheduler,
            reportReader: reportReader,
            calendar: aggregator.calendar,
            now: now,
        )
        // The reader runs in *this* (app) process and shares the controller's
        // store, calendar, and attributor so the published snapshot's day/year
        // line up with everything else the controller reports.
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
        widgetPublisher = widgets
        // After each committed GPS persist, reconcile the badge/reminders and
        // republish the widget snapshot. A live single sample uses the cheap
        // change-detection unless a drain also re-persisted other days; a
        // resume/drain-only batch reconciles fully and publishes only if it
        // actually persisted anything.
        locationIngestor = LocationIngestor(
            store: store,
            locationSource: locationSource,
            calendar: aggregator.calendar,
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
        journal = DayJournal(
            store: store,
            aggregator: aggregator,
            reminders: reminders,
            widgets: widgets,
        )
        backupCoordinator = BackupCoordinator(store: store, widgets: widgets)
    }

    // MARK: - Ingestion

    public func ingest(_ sample: LocationSample) async throws {
        try await journal.ingest(sample)
    }

    public func ingest(_ samples: [LocationSample]) async throws {
        try await journal.ingest(samples)
    }

    // MARK: - Retroactive entry

    public func addManualSample(_ sample: LocationSample) async throws {
        try await journal.addManualSample(sample)
    }

    public func addManualDay(date: Date, regions: Set<Region>) async throws {
        try await journal.addManualDay(date: date, regions: regions)
    }

    public func overrideDay(date: Date, regions: Set<Region>) async throws {
        try await journal.overrideDay(date: date, regions: regions)
    }

    public func clearManualDay(date: Date) async throws {
        try await journal.clearManualDay(date: date)
    }

    public func addManualDays(
        from start: Date,
        through end: Date,
        regions: Set<Region>,
    ) async throws {
        try await journal.addManualDays(from: start, through: end, regions: regions)
    }

    // MARK: - Evidence

    public func addEvidence(_ evidence: Evidence, blob: Data? = nil) async throws {
        try await journal.addEvidence(evidence, blob: blob)
    }

    public func evidence(for year: Int) async throws -> [Evidence] {
        try await journal.evidence(for: year)
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        try await journal.evidenceBlob(for: id)
    }

    // MARK: - Reporting

    public func yearReport(for year: Int) async throws -> YearReport {
        try await reportReader.yearReport(for: year)
    }

    /// The raw coordinates recorded inside `region` during `year`, grouped by
    /// day, so the Elsewhere drill-in can map and name where you actually were.
    /// Reads the same samples the report is built from; manual overlays don't
    /// contribute coordinates (see `DayAggregator.locations`).
    public func locations(in region: Region, year: Int) async throws -> [RegionDayLocations] {
        try await reportReader.locations(in: region, year: year)
    }

    /// One representative coordinate per region for `year` — the most heavily
    /// sampled spot in each — so the Elsewhere cards can show a "where" teaser
    /// with a single geocode per region.
    public func representativeCoordinates(for year: Int) async throws -> [Region: Coordinate] {
        try await reportReader.representativeCoordinates(for: year)
    }

    public func clearYear(_ year: Int) async throws {
        try await journal.clearYear(year)
    }

    public func eraseAllData() async throws {
        try await journal.eraseAllData()
    }

    /// Return the controller to a clean slate for the app's "erase all data &
    /// reset" teardown: stop GPS so nothing writes into the wiped store, then
    /// erase everything and reconcile the badge/reminders and widget against the
    /// now-empty data (`eraseAllData()`).
    ///
    /// This owns *what* gets cleared in Core, so the caller (`WhereModel`) only
    /// mirrors the outcome into its own UI state and clears app preferences
    /// (UserDefaults), which aren't Core data. Throws on persistence failure so
    /// the caller can surface it rather than silently half-erasing.
    public func reset() async throws {
        await stopGPS()
        try await eraseAllData()
    }

    // MARK: - Backup

    /// Transitional aliases so call sites (`SettingsView`, `WhereModel`) keep
    /// compiling while `ImportStrategy`/`ImportSummary` live on
    /// `BackupCoordinator`. Removed in `ctl-dissolve`.
    public typealias ImportStrategy = BackupCoordinator.ImportStrategy
    public typealias ImportSummary = BackupCoordinator.ImportSummary

    public func exportBackup() async throws -> URL {
        try await backupCoordinator.exportBackup()
    }

    public func importBackup(
        from url: URL,
        strategy: ImportStrategy,
        onProgress: @Sendable (Double) -> Void = { _ in },
    ) async throws -> ImportSummary {
        try await backupCoordinator.importBackup(
            from: url,
            strategy: strategy,
            onProgress: onProgress,
        )
    }

    // MARK: - GPS lifecycle

    /// Begin (or resume) GPS ingestion. Idempotent and safe to drive from
    /// multiple call sites (scene activation + a manual toggle); delegates to
    /// the `LocationIngestor`, which owns the monitoring + stream lifecycle.
    public func startGPS() async {
        await locationIngestor.start()
    }

    /// Pause GPS ingestion by stopping the underlying location monitoring.
    /// Idempotent and safe to call from teardown paths that may run before any
    /// `startGPS()`. The ingestion task is left running (see `LocationIngestor`)
    /// and idles until monitoring resumes.
    public func stopGPS() async {
        await locationIngestor.stop()
    }

    public func requestLocationPermission() async throws {
        try await locationIngestor.requestPermission()
    }

    /// The current location authorization status.
    public func authorizationStatus() async -> LocationAuthorizationStatus {
        await locationIngestor.authorizationStatus()
    }

    /// Live stream of authorization-status changes (system prompt results and
    /// Settings-app changes). Subscribe once and iterate.
    public func authorizationUpdates() async -> AsyncStream<LocationAuthorizationStatus> {
        await locationIngestor.authorizationUpdates()
    }

    /// Whether GPS monitoring is currently active. Exposed so the view-model
    /// can reconcile its tracking flag with reality after launch.
    public var isTrackingActive: Bool {
        get async { await locationIngestor.isActive }
    }

    /// Number of samples currently waiting to be re-persisted. Exposed for
    /// tests; production callers should treat this as opaque.
    public var retryQueueDepth: Int {
        get async { await locationIngestor.retryQueueDepth }
    }

    // MARK: - Widgets

    /// Recompute and publish the widget snapshot from whatever the store
    /// currently holds, without needing a mutation first. The widget extension
    /// only ever reads the published App Group file, so on a cold launch (no
    /// writes yet this session) or when the app returns to the foreground on a
    /// new calendar day, the widget would otherwise keep showing a stale — or
    /// empty — snapshot until the next write. The app's lifecycle hooks call
    /// this on launch and on activation; the publisher's freshness gate decides
    /// whether a rebuild is actually needed.
    public func refreshWidgetSnapshot() async {
        await widgetPublisher.refreshIfStale()
    }

    // MARK: - Logging reminders

    /// Set the user's reminder intent (enabled + time of day), request
    /// notification permission when enabling, then reconcile the scheduled
    /// reminders and badge. Safe to call on every launch and whenever the user
    /// changes the setting.
    public func configureReminders(enabled: Bool, time: ReminderTime) async {
        await reminderReconciler.configure(enabled: enabled, time: time)
    }

    /// Explicitly drive the notification permission prompt (e.g. from a
    /// Settings toggle). Returns whether the app is authorized afterward.
    @discardableResult
    public func requestNotificationAuthorization() async -> Bool {
        await reminderReconciler.requestAuthorization()
    }

    /// Whether the app is currently authorized to post reminders / set the
    /// badge, so the UI can surface an "open Settings" affordance.
    public func notificationAuthorizationGranted() async -> Bool {
        await reminderReconciler.isAuthorized()
    }

    // MARK: - Daily summary

    /// Set the user's daily-summary intent (enabled + time of day), request
    /// notification permission when enabling, then reconcile the scheduled
    /// summary notification. Safe to call on every launch and whenever the user
    /// changes the setting.
    public func configureDailySummary(enabled: Bool, time: ReminderTime) async {
        await summaryReconciler.configure(enabled: enabled, time: time)
    }
}
