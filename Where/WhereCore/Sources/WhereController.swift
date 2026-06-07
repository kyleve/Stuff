import Foundation
import os

/// Top-level API for the Where feature. Composes a `WhereStore`
/// (persistence) and a `LocationSource` (GPS) behind a small,
/// testable surface.
///
/// - GPS sampling is opt-in: callers invoke `startGPS()` once the user grants
///   authorization. Ingestion runs in an unstructured `Task` owned by the
///   actor; `stopGPS()` pauses the underlying monitoring while leaving the
///   task alive (so the stream can be resumed), and `deinit` cancels it.
/// - Retroactive entry uses `addManualSample(_:)` (a single coordinate) or
///   `addManualDay(date:regions:)` (an authoritative day overlay that unions
///   with whatever GPS produced for that day).
/// - `yearReport(for:)` reads everything in the requested calendar year via
///   the injected `DayAggregator` and returns a snapshot-stable `YearReport`.
public actor WhereController {
    private let store: any WhereStore
    private let locationSource: any LocationSource
    private let attributor: RegionAttributor
    private let aggregator: DayAggregator
    private let reminderScheduler: any LoggingReminderScheduling
    private let now: @Sendable () -> Date

    private var ingestTask: Task<Void, Never>?

    /// User intent for the daily "log before the day ends" reminder. Disabled
    /// until the UI calls `configureReminders(enabled:time:)`, so a freshly
    /// constructed controller never schedules anything on its own.
    private var reminderConfig = ReminderConfiguration()

    /// The start-of-day we last reconciled while today already had presence.
    /// Lets the GPS ingest path skip a full re-scan once today is covered
    /// (significant-change events can fire many times a day).
    private var todayCoveredByReconcile: Date?

    /// How many days past today the per-day reminders are scheduled ahead, so a
    /// stretch where the app never runs still has reminders queued. Today plus
    /// this many days.
    private static let reminderWindowDays = 6

    private struct ReminderConfiguration {
        var enabled = false
        var time: ReminderTime = .defaultEvening
    }

    /// Whether the underlying location monitoring is currently active. Tracked
    /// separately from `ingestTask` because the ingestion task outlives a
    /// `stopGPS()` pause (see `startGPS()` for why).
    private var isMonitoring = false

    /// Samples whose persist call failed (e.g. transient SwiftData / CloudKit
    /// error). Drained before each new GPS save and on the next `startGPS()`
    /// so a brief I/O outage doesn't silently drop measurements.
    private var retryQueue: [LocationSample] = []

    /// Hard cap on the retry queue. Once reached, the oldest pending sample
    /// is dropped to make room for the newest. Sized to ~12 hours of
    /// significant-change/Visits ingestion (which fires on the order of
    /// minutes, not seconds), so reaching the cap means something is very
    /// wrong with persistence and we'd rather keep recent data than ancient.
    private static let retryQueueCapacity = 1000

    private static let logger = Logger(subsystem: "com.stuff.where", category: "WhereController")

    public init(
        store: any WhereStore,
        locationSource: any LocationSource,
        attributor: RegionAttributor = .shared,
        aggregator: DayAggregator = DayAggregator(),
        reminderScheduler: any LoggingReminderScheduling = UserNotificationReminderScheduler(),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.store = store
        self.locationSource = locationSource
        self.attributor = attributor
        self.aggregator = aggregator
        self.reminderScheduler = reminderScheduler
        self.now = now
    }

    deinit {
        ingestTask?.cancel()
    }

    // MARK: - Ingestion

    public func ingest(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
    }

    // MARK: - Retroactive entry

    public func addManualSample(_ sample: LocationSample) async throws {
        try await store.perform { try await store.add(sample: sample) }
    }

    public func addManualDay(date: Date, regions: Set<Region>) async throws {
        let key = aggregator.calendar.startOfDay(for: date)
        let presence = DayPresence(date: key, regions: regions)
        try await store.perform { try await store.setManualDay(presence) }
        await reconcileReminders()
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
        await reconcileReminders()
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
        let interval = aggregator.yearInterval(year: year)
        let samples = try await store.samples(in: interval)
        let manuals = try await store.manualDays(in: interval)
        return aggregator.report(
            for: year,
            samples: samples,
            manualDays: manuals,
            attributor: attributor,
        )
    }

    public func clearYear(_ year: Int) async throws {
        let interval = aggregator.yearInterval(year: year)
        try await store.perform { try await store.clear(in: interval) }
        await reconcileReminders()
    }

    // MARK: - GPS lifecycle

    /// Begin (or resume) GPS ingestion. Idempotent: a second call while
    /// monitoring is already active is a no-op, so the lifecycle is safe to
    /// drive from multiple call sites (e.g. scene activation + a manual
    /// toggle).
    ///
    /// The task that drains `locationSource.sampleStream` is created once and
    /// then kept alive for the controller's lifetime; `stopGPS()` only pauses
    /// the underlying monitoring. Cancelling that task would terminate the
    /// single-consumer `AsyncStream`, so a later `startGPS()` would iterate an
    /// already-finished stream and silently drop every subsequent sample.
    public func startGPS() async {
        guard !isMonitoring else { return }
        isMonitoring = true
        await locationSource.start()
        // Flush anything that failed to persist before this session
        // started, before we (re)attach the stream consumer.
        _ = await drainRetryQueue()
        // Refresh the badge / reminders against whatever the resumed session
        // already knows about (e.g. after a background relaunch).
        await reconcileReminders()
        guard ingestTask == nil else { return }
        let stream = locationSource.sampleStream
        ingestTask = Task { [weak self] in
            for await sample in stream {
                if Task.isCancelled { break }
                guard let self else { break }
                await processIngestedSample(sample)
            }
        }
    }

    /// Persist one GPS-sourced sample, falling back to the retry queue
    /// on failure. Drains any backlog first so a single transient
    /// outage doesn't permanently reorder samples on disk.
    private func processIngestedSample(_ sample: LocationSample) async {
        var changedDays = await drainRetryQueue()
        do {
            try await store.perform { try await store.add(sample: sample) }
            changedDays.insert(aggregator.calendar.startOfDay(for: sample.timestamp))
            await reconcileRemindersAfterIngest(changedDays: changedDays)
        } catch {
            // Persistence failures (SwiftData save, CloudKit, etc.)
            // are surfaced via `os.Logger` instead of being silently
            // dropped. The stream keeps running so a transient error
            // doesn't stop tracking, and the sample is queued for
            // retry on the next save attempt.
            Self.logger.error(
                "Failed to persist GPS sample \(sample.id, privacy: .public): \(error.localizedDescription, privacy: .public)",
            )
            enqueueForRetry(sample)
        }
    }

    private func enqueueForRetry(_ sample: LocationSample) {
        if retryQueue.count >= Self.retryQueueCapacity {
            retryQueue.removeFirst()
        }
        retryQueue.append(sample)
    }

    /// Try to flush every queued sample exactly once. Anything that
    /// still fails is re-queued at the tail; the next call gets the
    /// chance to retry it.
    private func drainRetryQueue() async -> Set<Date> {
        guard !retryQueue.isEmpty else { return [] }
        let pending = retryQueue
        retryQueue.removeAll(keepingCapacity: true)
        var persistedDays: Set<Date> = []
        for sample in pending {
            do {
                try await store.perform { try await store.add(sample: sample) }
                persistedDays.insert(aggregator.calendar.startOfDay(for: sample.timestamp))
            } catch {
                Self.logger.error(
                    "Retry still failing for GPS sample \(sample.id, privacy: .public): \(error.localizedDescription, privacy: .public)",
                )
                enqueueForRetry(sample)
            }
        }
        return persistedDays
    }

    /// Number of samples currently waiting to be re-persisted. Exposed
    /// for tests; production callers should treat this as opaque.
    public var retryQueueDepth: Int {
        retryQueue.count
    }

    /// Pause GPS ingestion by stopping the underlying location monitoring.
    /// Idempotent and safe to call from teardown paths that may run before
    /// any `startGPS()` (e.g. scene background, error recovery). The
    /// ingestion task is intentionally left running (see `startGPS()`); it
    /// simply idles until monitoring resumes. The task is torn down on
    /// `deinit`.
    public func stopGPS() async {
        guard isMonitoring else { return }
        isMonitoring = false
        await locationSource.stop()
    }

    public func requestLocationPermission() async throws {
        try await locationSource.requestPermission()
    }

    /// The current location authorization status.
    public func authorizationStatus() async -> LocationAuthorizationStatus {
        await locationSource.currentAuthorization()
    }

    /// Live stream of authorization-status changes (system prompt results and
    /// Settings-app changes). Subscribe once and iterate.
    public func authorizationUpdates() -> AsyncStream<LocationAuthorizationStatus> {
        locationSource.authorizationUpdates
    }

    /// Whether GPS monitoring is currently active. Exposed so the view-model
    /// can reconcile its tracking flag with reality after launch.
    public var isTrackingActive: Bool {
        isMonitoring
    }

    // MARK: - Logging reminders

    /// Set the user's reminder intent (enabled + time of day), request
    /// notification permission when enabling, then reconcile the scheduled
    /// reminders and badge. Safe to call on every launch and whenever the user
    /// changes the setting.
    public func configureReminders(enabled: Bool, time: ReminderTime) async {
        reminderConfig = ReminderConfiguration(enabled: enabled, time: time)
        if enabled {
            _ = await reminderScheduler.requestAuthorization()
        }
        await reconcileReminders()
    }

    /// Explicitly drive the notification permission prompt (e.g. from a
    /// Settings toggle). Returns whether the app is authorized afterward.
    @discardableResult
    public func requestNotificationAuthorization() async -> Bool {
        await reminderScheduler.requestAuthorization()
    }

    /// Whether the app is currently authorized to post reminders / set the
    /// badge, so the UI can surface an "open Settings" affordance.
    public func notificationAuthorizationGranted() async -> Bool {
        await reminderScheduler.isAuthorized()
    }

    /// Cheap reconcile for the GPS ingest path: only runs when reminders are on
    /// and today isn't already known to be covered, so a burst of
    /// significant-change samples doesn't trigger a full-year scan each time.
    private func reconcileRemindersAfterIngest(changedDays: Set<Date>) async {
        guard reminderConfig.enabled else { return }
        let today = aggregator.calendar.startOfDay(for: now())
        let changedDayNeedsReconcile = changedDays.contains { $0 != today }
        guard todayCoveredByReconcile != today || changedDayNeedsReconcile else { return }
        await reconcileReminders()
    }

    /// Recompute the current-year missing-day picture from the store and push
    /// it to the scheduler: the badge is the total unlogged days this year, and
    /// a rolling window of upcoming unlogged days gets per-day reminders. This
    /// is the single source of truth for "recorded successfully -> drop today's
    /// reminder and lower the badge".
    private func reconcileReminders() async {
        guard reminderConfig.enabled else {
            await reminderScheduler.reconcile(
                badgeCount: 0,
                scheduleDays: [],
                reminderTime: reminderConfig.time,
                enabled: false,
            )
            todayCoveredByReconcile = nil
            return
        }

        let calendar = aggregator.calendar
        let today = calendar.startOfDay(for: now())
        let year = calendar.component(.year, from: today)
        do {
            let report = try await yearReport(for: year)
            let present = Set(report.days.map { calendar.startOfDay(for: $0.date) })
            // The badge backlog is *past* misses only — today is still loggable,
            // so it's covered by the forward-looking reminder below rather than
            // counted as missed (otherwise the app would warn every morning).
            let backlog = MissingDays.missingDayKeys(
                year: year,
                through: MissingDays.backlogCutoff(asOf: now(), calendar: calendar),
                present: present,
                calendar: calendar,
            )
            let windowEnd = calendar.date(
                byAdding: .day,
                value: Self.reminderWindowDays,
                to: today,
            ) ?? today
            let scheduleDays = today
                .calendarDays(through: windowEnd, in: calendar)
                .filter { !present.contains($0) }
            await reminderScheduler.reconcile(
                badgeCount: backlog.count,
                scheduleDays: scheduleDays,
                reminderTime: reminderConfig.time,
                enabled: true,
            )
            todayCoveredByReconcile = present.contains(today) ? today : nil
        } catch {
            Self.logger.error(
                "Failed to reconcile logging reminders: \(error.localizedDescription, privacy: .public)",
            )
        }
    }
}
