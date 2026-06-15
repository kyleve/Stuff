import Foundation

/// Top-level API for the Where feature. Composes a `WhereStore`
/// (persistence) with focused collaborators — a `LocationIngestor` (GPS), a
/// `WidgetSnapshotPublisher`, and the reminder / daily-summary reconcilers —
/// behind a small, testable surface.
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
    private let store: any WhereStore
    private let aggregator: DayAggregator
    private let reportReader: ReportReader
    private let backupService = BackupService()
    private let reminderReconciler: ReminderReconciler
    private let summaryReconciler: DailySummaryReconciler
    private let widgetPublisher: WidgetSnapshotPublisher
    private let locationIngestor: LocationIngestor

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
        self.store = store
        self.aggregator = aggregator
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
    }

    // MARK: - Ingestion

    public func ingest(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
        await widgetPublisher.publishAfterIngest(of: sample)
    }

    /// Persist many samples in a *single* transaction, rebuilding the widget
    /// snapshot once at the end instead of once per sample. The single-sample
    /// `ingest(_:)` is the right call for live GPS (events arrive minutes
    /// apart), but bulk loads — test fixtures, future bulk imports — would
    /// otherwise open one transaction *and* re-aggregate the whole year per
    /// sample, which is quadratic in the batch size. An empty batch is a no-op
    /// (no transaction, no snapshot publish).
    public func ingest(_ samples: [LocationSample]) async throws {
        guard !samples.isEmpty else { return }
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        await widgetPublisher.publish()
    }

    // MARK: - Retroactive entry

    public func addManualSample(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
        await widgetPublisher.publish()
    }

    public func addManualDay(date: Date, regions: Set<Region>) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        let presence = DayPresence(date: key, regions: regions)
        try await store.perform { try await store.setManualDay(presence) }
        await reminderReconciler.reconcile()
        await widgetPublisher.publish()
    }

    /// Authoritatively set the regions for a single calendar day, *replacing*
    /// whatever GPS (or a prior manual overlay) attributed to it. Unlike
    /// `addManualDay`, this does not union with GPS — it's the "correct a
    /// wrong attribution" path. The raw GPS samples are left untouched, so the
    /// fix is non-destructive and undone by `clearManualDay(date:)`.
    public func overrideDay(date: Date, regions: Set<Region>) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        let presence = DayPresence(date: key, regions: regions, isAuthoritative: true)
        try await store.perform { try await store.setManualDay(presence) }
        await reminderReconciler.reconcile()
        await widgetPublisher.publish()
    }

    /// Drop the manual overlay for a single calendar day, restoring the
    /// GPS-derived attribution (the relabel "reset to GPS" path). A no-op when
    /// the day has no manual record. Raw samples are never touched, so this
    /// simply lets the aggregator fall back to whatever GPS recorded.
    public func clearManualDay(date: Date) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        try await store.perform { try await store.clearManualDay(key) }
        await reminderReconciler.reconcile()
        await widgetPublisher.publish()
    }

    /// Assert `regions` for every calendar day in the inclusive range
    /// `start...end` (handy for backfilling a trip). Both bounds are
    /// normalized to start-of-day in the aggregator's calendar, and the
    /// whole range is written inside a single `perform` transaction so the
    /// backfill commits (or rolls back) atomically. A `start` later than
    /// `end` is treated as an empty range and writes nothing.
    public func addManualDays(
        from start: Date,
        through end: Date,
        regions: Set<Region>,
    ) async throws {
        // `calendarDays` returns an immutable array, so the `@Sendable`
        // transaction body captures a `let` rather than a mutable cursor
        // across the concurrency boundary.
        let dayKeys = start.calendarDays(through: end, in: aggregator.calendar)
        guard !dayKeys.isEmpty else { return }
        try await store.perform {
            for day in dayKeys {
                try await store.setManualDay(DayPresence(date: day, regions: regions))
            }
        }
        await reminderReconciler.reconcile()
        await widgetPublisher.publish()
    }

    // MARK: - Evidence

    public func addEvidence(_ evidence: Evidence, blob: Data? = nil) async throws {
        try await store.perform { try await store.write(evidence: evidence, blob: blob) }
    }

    public func evidence(for year: Int) async throws -> [Evidence] {
        try await store.evidence(in: aggregator.yearInterval(year: year))
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        try await store.evidenceBlob(for: id)
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
        let interval = aggregator.yearInterval(year: year)
        try await store.perform { try await store.clear(in: interval) }
        await reminderReconciler.reconcile()
        await widgetPublisher.publish()
    }

    /// Erase every sample, manual day, and piece of evidence in the store, then
    /// reconcile the reminder schedule/badge and republish an (now empty) widget
    /// snapshot. The store half of `reset()`.
    ///
    /// Mirrors `clearYear`'s reconciliation so the badge/reminders reflect the
    /// now-empty store immediately, rather than relying on a later launch step.
    public func eraseAllData() async throws {
        try await store.perform { try await store.clearAll() }
        await reminderReconciler.reconcile()
        await widgetPublisher.publish()
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

    /// How an imported backup combines with whatever is already on the device.
    public enum ImportStrategy: Sendable {
        /// Upsert the imported rows into the existing data (by `id` for
        /// samples/evidence, by day key for manual days), leaving anything
        /// not present in the file untouched.
        case merge
        /// Erase the whole store first so the device ends up mirroring the
        /// file exactly.
        case replace
    }

    /// Counts of what an import wrote, for a user-facing confirmation.
    public struct ImportSummary: Sendable, Hashable {
        public let sampleCount: Int
        public let evidenceCount: Int
        public let manualDayCount: Int

        public init(sampleCount: Int, evidenceCount: Int, manualDayCount: Int) {
            self.sampleCount = sampleCount
            self.evidenceCount = evidenceCount
            self.manualDayCount = manualDayCount
        }
    }

    /// Serialize the entire store (all three tables plus evidence blobs) to a
    /// `.zip` in the temporary directory and return its URL. The caller owns
    /// the file: share it, then delete it (or its parent directory).
    public func exportBackup() async throws -> URL {
        let samples = try await store.allSamples()
        let evidence = try await store.allEvidence()
        let manualDays = try await store.allManualDays()
        var blobs: [UUID: Data] = [:]
        for item in evidence {
            if let blob = try await store.evidenceBlob(for: item.id) {
                blobs[item.id] = blob
            }
        }
        let backupService = backupService
        return try await Task.detached(priority: .utility) {
            try backupService.makeArchiveFile(
                samples: samples,
                evidence: evidence,
                manualDays: manualDays,
                blobs: blobs,
            )
        }.value
    }

    /// Read a backup `.zip` and write its contents back into the store inside
    /// a single transaction. `.replace` wipes the store first; `.merge` relies
    /// on the store's upsert semantics. Returns counts of what was imported.
    ///
    /// `onProgress` is invoked with a fraction in `0...1` as rows are written,
    /// throttled to whole-percent changes so a large import doesn't flood the
    /// caller. It runs on the store's executor; a UI caller should marshal it
    /// back to the main actor (e.g. via an `AsyncStream`).
    public func importBackup(
        from url: URL,
        strategy: ImportStrategy,
        onProgress: @Sendable (Double) -> Void = { _ in },
    ) async throws -> ImportSummary {
        // Files handed over by the document picker are security-scoped; we
        // must bracket the read with start/stop access or `Data(contentsOf:)`
        // fails with a permissions error.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let backupService = backupService
        let result = try await Task.detached(priority: .utility) {
            try backupService.readArchive(at: url)
        }.value
        let archive = result.archive
        let blobs = result.blobs
        let total = archive.samples.count + archive.evidence.count + archive.manualDays.count

        try await store.perform {
            if strategy == .replace {
                try await store.clearAll()
            }
            // `completed`/`report` are local to this `@Sendable` block, so the
            // running count never crosses the actor boundary; only the
            // throttled fraction is handed to `onProgress`.
            var completed = 0
            var lastPercent = -1
            func report() {
                completed += 1
                guard total > 0 else { return }
                let percent = Int(Double(completed) / Double(total) * 100)
                guard percent != lastPercent else { return }
                lastPercent = percent
                onProgress(Double(completed) / Double(total))
            }
            for sample in archive.samples {
                try await store.add(sample: sample)
                report()
            }
            for item in archive.evidence {
                try await store.write(evidence: item, blob: blobs[item.id])
                report()
            }
            for day in archive.manualDays {
                try await store.setManualDay(day)
                report()
            }
        }
        await widgetPublisher.publish()

        return ImportSummary(
            sampleCount: archive.samples.count,
            evidenceCount: archive.evidence.count,
            manualDayCount: archive.manualDays.count,
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
