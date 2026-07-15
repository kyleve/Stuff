import Foundation
import LogKit

/// Owns live GPS ingestion: the location-monitoring lifecycle, the
/// single-consumer sample stream, the retry queue (mirrored to a durable
/// `LocationOutbox` so it survives transient persistence failures *and* app
/// relaunches), and authorization. Persisted samples are reported back through
/// an injected post-persist hook, so this actor stays unaware of reminders and
/// widgets — the assembler wires those in.
public actor LocationIngestor {
    /// What a persist batch changed, handed to the post-persist hook so the
    /// assembler can reconcile reminders + republish widgets appropriately.
    struct IngestOutcome {
        /// Day keys whose presence may have changed.
        let changedDays: Set<Date>
        /// The single live GPS sample just ingested, when this batch came from
        /// the live stream — enables the widget's cheap same-day/region skip.
        /// `nil` for a resume/drain-only batch, which reconciles fully.
        let liveSample: LocationSample?
        /// Whether the widget must do a full rebuild rather than the cheap
        /// single-sample change-detection. Set when draining re-persisted
        /// samples for *other* days alongside the live one.
        let needsFullWidgetRebuild: Bool
    }

    /// Invoked after each committed persist so the assembler can reconcile the
    /// badge/reminders and republish the widget snapshot.
    typealias PostPersistHook = @Sendable (IngestOutcome) async -> Void

    private let store: any WhereStore
    private let locationSource: any LocationSource
    private let calendar: Calendar
    private let onPersisted: PostPersistHook
    /// Durable mirror of `retryQueue`, so a backlog survives the process dying
    /// mid-outage. Loaded once on the first `start()` and rewritten whenever the
    /// queue changes; cleared by `quiesce()`.
    private let outbox: any LocationOutbox

    private var ingestTask: Task<Void, Never>?

    /// The in-flight one-shot capture spawned by `captureTodayIfNeeded(now:)`,
    /// if any. Tracked so overlapping foreground / launch triggers coalesce onto
    /// a single fix (single-flight) and so teardown can cancel it. Cleared when
    /// the work completes.
    private var captureTask: Task<Void, Never>?

    /// The persist the stream loop is currently awaiting, if any. Tracked so
    /// `quiesce()` can wait for an in-flight write to commit before a teardown
    /// wipes the store — gating alone can't, since a persist that already
    /// started has an actor hop across `store.perform`.
    private var inFlightIngest: Task<Void, Never>?

    /// Whether the underlying location monitoring is currently active. Tracked
    /// separately from `ingestTask` because the ingestion task outlives a
    /// `stop()` pause (see `start()` for why).
    private var isMonitoring = false

    /// Whether streamed samples are currently persisted. Shut by `quiesce()` so
    /// a teardown can wipe the store without a late GPS event writing into it,
    /// and re-opened by the next `start()`.
    private var acceptsSamples = true

    /// Samples whose persist call failed (e.g. transient SwiftData / CloudKit
    /// error). Drained before each new GPS save and on the next `start()` so a
    /// brief I/O outage doesn't silently drop measurements. Mirrored to `outbox`
    /// on every change so the backlog also survives a relaunch.
    private var retryQueue: [LocationSample] = []

    /// Whether the durable backlog has been merged into `retryQueue` yet. Loaded
    /// exactly once (first `start()`); afterwards `retryQueue` is authoritative
    /// and a reload could lose items the outbox failed to persist.
    private var didLoadDurableBacklog = false

    /// Hard cap on the retry queue. Once reached, the oldest pending sample is
    /// dropped to make room for the newest. Production uses ~12 hours of
    /// significant-change/Visits ingestion; tests inject a smaller cap.
    private let retryQueueCapacity: Int

    private static let logger = WhereLog.channel(.locationIngestor)

    init(
        store: any WhereStore,
        locationSource: any LocationSource,
        calendar: Calendar,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
        retryQueueCapacity: Int = 1000,
        onPersisted: @escaping PostPersistHook,
    ) {
        precondition(retryQueueCapacity > 0, "retryQueueCapacity must be positive")
        self.store = store
        self.locationSource = locationSource
        self.calendar = calendar
        self.outbox = outbox
        self.retryQueueCapacity = retryQueueCapacity
        self.onPersisted = onPersisted
    }

    deinit {
        ingestTask?.cancel()
        captureTask?.cancel()
    }

    /// Begin (or resume) GPS ingestion. Idempotent: a second call while
    /// monitoring is already active is a no-op, so the lifecycle is safe to
    /// drive from multiple call sites (e.g. scene activation + a manual toggle).
    ///
    /// The task that drains `locationSource.sampleStream` is created once and
    /// then kept alive for the actor's lifetime; `stop()` only pauses the
    /// underlying monitoring. Cancelling that task would terminate the
    /// single-consumer `AsyncStream`, so a later `start()` would iterate an
    /// already-finished stream and silently drop every subsequent sample.
    public func start() async {
        // Re-open the sample gate a prior `quiesce()` may have shut (e.g. the
        // relaunch after a reset resumes ingestion here).
        acceptsSamples = true
        guard !isMonitoring else { return }
        isMonitoring = true
        await locationSource.start()
        Self.logger.info("GPS monitoring started")
        // Seed the in-memory queue from the durable backlog once, so samples that
        // failed to persist in a prior launch get retried now.
        if !didLoadDurableBacklog {
            didLoadDurableBacklog = true
            let restored = await outbox.load()
            if !restored.isEmpty {
                Self.logger.info("Restored \(restored.count) sample(s) from durable retry backlog")
            }
            retryQueue = restored + retryQueue
        }
        // Flush anything that failed to persist before this session started,
        // before we (re)attach the stream consumer.
        let drainedDays = await drainRetryQueue()
        await onPersisted(IngestOutcome(
            changedDays: drainedDays,
            liveSample: nil,
            needsFullWidgetRebuild: !drainedDays.isEmpty,
        ))
        guard ingestTask == nil else { return }
        let stream = locationSource.sampleStream
        ingestTask = Task { [weak self] in
            for await sample in stream {
                if Task.isCancelled { break }
                guard let self else { break }
                await ingest(sample)
            }
        }
    }

    /// Pause GPS ingestion by stopping the underlying location monitoring.
    /// Idempotent and safe to call from teardown paths that may run before any
    /// `start()`. The ingestion task is intentionally left running (see
    /// `start()`); it idles until monitoring resumes, and is torn down on
    /// `deinit`.
    public func stop() async {
        guard isMonitoring else { return }
        isMonitoring = false
        await locationSource.stop()
        Self.logger.info("GPS monitoring stopped")
    }

    /// Stop ingestion and guarantee nothing else writes until the next
    /// `start()`: stop monitoring, refuse further streamed samples, wait for any
    /// persist already in flight to commit, then drop the retry backlog — both
    /// the in-memory queue and its durable outbox. The app's reset/erase teardown
    /// awaits this before wiping the store (see `WhereServices.reset`), so a late
    /// GPS event can't repopulate it and a stale backlog can't re-drain into it on
    /// the next `start()`.
    ///
    /// Unlike `stop()` (a normal pause that keeps the backlog for when
    /// monitoring resumes), `quiesce()` clears it — the store is about to be
    /// erased, so those samples must not come back.
    public func quiesce() async {
        acceptsSamples = false
        isMonitoring = false
        // Cancel any in-flight one-shot capture; even if its fix still lands
        // after this, the `acceptsSamples` gate in `ingest(_:)` drops it.
        captureTask?.cancel()
        captureTask = nil
        await locationSource.stop()
        // Let an already-started persist (and any retry re-enqueue it performs)
        // settle first, then clear the backlog — so nothing re-adds after.
        await inFlightIngest?.value
        retryQueue.removeAll()
        // Clear the durable mirror too; the store is about to be erased, so the
        // backlog must not re-drain into it on the next launch.
        await outbox.save([])
        Self.logger.info("GPS ingestion quiesced; retry backlog cleared")
    }

    /// Whether GPS monitoring is currently active. Exposed so the view-model can
    /// reconcile its tracking flag with reality after launch.
    public var isActive: Bool {
        isMonitoring
    }

    /// Number of samples currently waiting to be re-persisted. Exposed for
    /// tests; production callers should treat this as opaque.
    public var retryQueueDepth: Int {
        retryQueue.count
    }

    public func requestPermission() async throws {
        try await locationSource.requestPermission()
    }

    /// Best-effort one-shot GPS fix for "where is the device right now", used to
    /// stamp a manual entry's audit trail. Returns `nil` when no fix is
    /// available (permission not granted, timeout); the caller records the entry
    /// either way. Routed through the ingestor so the UI never touches the
    /// `LocationSource` directly.
    public func currentLocation() async -> LocationSample? {
        await locationSource.requestCurrentLocation()
    }

    /// Fill in *today* with a best-effort one-shot GPS fix when the day has no
    /// GPS sample yet, so opening the app on a fresh day doesn't leave the
    /// calendar blank until passive monitoring (Visits / significant-change)
    /// next fires. Non-blocking: the fix (which can take up to ~10s) runs on an
    /// internal task so launch / foreground callers aren't held up — the
    /// persisted sample refreshes readers via the store's change signal.
    ///
    /// Single-flight: a call while a capture is already in flight is a no-op.
    /// Only a *GPS* sample suppresses the fix; a manual entry for today doesn't,
    /// since it isn't a passive-tracking data point. Whether to attempt this at
    /// all (the user's tracking intent + authorization) is the caller's gate;
    /// this stays safe regardless because `requestCurrentLocation()` returns
    /// `nil` when no fix is available.
    public func captureTodayIfNeeded(now: Date) {
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            await self?.performTodayCapture(now: now)
            await self?.clearCaptureTask()
        }
    }

    private func clearCaptureTask() {
        captureTask = nil
    }

    /// The body of `captureTodayIfNeeded(now:)`, run on `captureTask`.
    private func performTodayCapture(now: Date) async {
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            Self.logger.warning("Could not compute today's interval for foreground capture")
            return
        }
        let interval = DateInterval(start: startOfDay, end: endOfDay)
        do {
            let existing = try await store.samples(in: interval)
            if existing.contains(where: \.source.isGPS) { return }
        } catch {
            // Fail closed: if today's samples can't be read we skip rather than
            // risk logging a duplicate fix. Surfaced, not silently swallowed.
            Self.logger.warning(
                "Skipping foreground capture; could not read today's samples: \(error.localizedDescription)",
            )
            return
        }
        guard let sample = await locationSource.requestCurrentLocation() else { return }
        Self.logger.info("Captured one-shot foreground location for today")
        await ingest(sample)
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

    /// Gate and track a single streamed sample. A sample that arrives after a
    /// `quiesce()` (and before the next `start()`) is dropped rather than
    /// persisted, so a teardown that wipes the store can't be clobbered by a
    /// late GPS write. The persist is tracked in `inFlightIngest` so `quiesce()`
    /// can await it.
    private func ingest(_ sample: LocationSample) async {
        guard acceptsSamples else { return }
        let work = Task { [weak self] in
            guard let self else { return }
            await processIngestedSample(sample)
        }
        inFlightIngest = work
        await work.value
        inFlightIngest = nil
    }

    /// Persist one GPS-sourced sample, falling back to the retry queue on
    /// failure. Drains any backlog first so a single transient outage doesn't
    /// permanently reorder samples on disk.
    private func processIngestedSample(_ sample: LocationSample) async {
        let drainedDays = await drainRetryQueue()
        do {
            try await store.perform { try await store.add(sample: sample) }
            var changedDays = drainedDays
            changedDays.insert(calendar.startOfDay(for: sample.timestamp))
            await onPersisted(IngestOutcome(
                changedDays: changedDays,
                liveSample: sample,
                needsFullWidgetRebuild: !drainedDays.isEmpty,
            ))
        } catch {
            // Persistence failures (SwiftData save, CloudKit, etc.) are surfaced
            // via `os.Logger` rather than silently dropped. The stream keeps
            // running so a transient error doesn't stop tracking, and the sample
            // is queued for retry on the next save attempt.
            Self.logger.error(
                "Failed to persist GPS sample \(sample.id): \(error.localizedDescription)",
            )
            enqueueForRetry(sample)
            await outbox.save(retryQueue)
        }
    }

    private func enqueueForRetry(_ sample: LocationSample) {
        if retryQueue.count >= retryQueueCapacity {
            Self.logger.warning(
                "Retry queue at capacity (\(retryQueueCapacity)); dropping oldest queued GPS sample",
            )
            retryQueue.removeFirst()
        }
        retryQueue.append(sample)
    }

    /// Try to flush every queued sample exactly once. Anything that still fails
    /// is re-queued at the tail; the next call gets the chance to retry it. The
    /// durable backlog is rewritten to match the post-drain queue.
    private func drainRetryQueue() async -> Set<Date> {
        guard !retryQueue.isEmpty else { return [] }
        let pending = retryQueue
        retryQueue.removeAll(keepingCapacity: true)
        var persistedDays: Set<Date> = []
        for sample in pending {
            do {
                try await store.perform { try await store.add(sample: sample) }
                persistedDays.insert(calendar.startOfDay(for: sample.timestamp))
            } catch {
                Self.logger.error(
                    "Retry still failing for GPS sample \(sample.id): \(error.localizedDescription)",
                )
                enqueueForRetry(sample)
            }
        }
        if !persistedDays.isEmpty {
            Self.logger.info(
                "Drained retry backlog: persisted \(pending.count - retryQueue.count) sample(s) across \(persistedDays.count) day(s)",
            )
        }
        await outbox.save(retryQueue)
        return persistedDays
    }
}

#if DEBUG
    extension LocationIngestor {
        /// Enqueue a sample for retry without persisting. Tests use this to assert
        /// FIFO eviction at `retryQueueCapacity` without simulating hundreds of
        /// persistence failures.
        @_spi(Testing) public func testingEnqueueForRetry(_ sample: LocationSample) {
            enqueueForRetry(sample)
        }

        /// Sample IDs currently in the retry queue, in FIFO order.
        @_spi(Testing) public func testingRetryQueueSampleIDs() -> [UUID] {
            retryQueue.map(\.id)
        }
    }
#endif
