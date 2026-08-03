import Foundation
import PeriscopeCore

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
    private let recordingDeviceID: RecordingDeviceID
    private let calendar: Calendar
    private let onPersisted: PostPersistHook
    /// Durable mirror of `retryQueue`, so a backlog survives the process dying
    /// mid-outage. Loaded once on the first `start()` and rewritten whenever the
    /// queue changes; cleared only by `discardRetryBacklog()` (directly or via
    /// `quiesce()`).
    private let outbox: any LocationOutbox

    private var ingestTask: Task<Void, Never>?

    /// The in-flight one-shot capture spawned by `captureTodayIfNeeded(now:)`,
    /// if any. Tracked so overlapping foreground / launch triggers coalesce onto
    /// a single fix (single-flight) and so teardown can cancel it. Cleared when
    /// the work completes. This spans the (slow, up to ~10s) fix acquisition, so
    /// `pause()` cancels it but does *not* await it — see `capturePersistTask`.
    private var captureTask: Task<Void, Never>?

    /// The capture's *persist* step, once a fix is in hand — separate from
    /// `captureTask` (which also covers the slow fix) so `pause()` can await a
    /// commit already in progress without stalling on a slow GPS fix. A single
    /// writer (capture is single-flight via `captureTask`), so it never clobbers
    /// the stream loop's `inFlightIngest` the way a shared slot would.
    private var capturePersistTask: Task<Void, Never>?

    /// The persist the stream loop is currently awaiting, if any. Tracked so
    /// `pause()` can wait for an in-flight write to commit before a teardown
    /// wipes the store — gating alone can't, since a persist that already
    /// started has an actor hop across `store.perform`.
    private var inFlightIngest: Task<Void, Never>?

    /// Whether the underlying location monitoring is currently active. Tracked
    /// separately from `ingestTask` because the ingestion task outlives a
    /// `stop()` pause (see `start()` for why).
    private var isMonitoring = false

    /// Whether the resolved device policy currently authorizes automatic samples. Closed before
    /// registration, while policy is Off/unavailable, and during teardown. This is independent
    /// of background monitoring: an enabled When-In-Use device may take a foreground fix while
    /// monitoring remains paused.
    private var acceptsSamples = false
    /// Logical generation whose recording authority opened the sample gate. Every persist and
    /// retry uses this as an expected-epoch token, so a remote reset cannot restamp an in-flight
    /// old-authority sample into the new generation.
    private var authorizedDataEpochID: WhereDataEpochID?

    /// Earliest timestamp a newly delivered live sample may carry for the current authority
    /// window. Core Location can buffer callbacks before the stream consumer is installed; the
    /// cutoff prevents those pre-consent / Off-period samples from becoming authorized merely
    /// because they are consumed after recording turns On.
    private var acceptsSamplesSince: Date?

    /// Samples whose persist call failed (e.g. transient SwiftData / CloudKit
    /// error). Drained before each new GPS save and on the next `start()` so a
    /// brief I/O outage doesn't silently drop measurements. Mirrored to `outbox`
    /// on every change so the backlog also survives a relaunch.
    private var retryQueue: [LocationOutboxEntry] = []

    #if DEBUG
        /// Test-only acknowledgement that the stream loop finished processing
        /// an emitted sample. This lets rejection tests wait for consumption
        /// itself rather than assume a scheduler delay was long enough.
        private var testingConsumedSampleIDs: Set<UUID> = []
    #endif

    /// Whether the durable backlog has been merged into `retryQueue` yet. Loaded
    /// exactly once (first `start()`); afterwards `retryQueue` is authoritative
    /// and a reload could lose items the outbox failed to persist.
    private var didLoadDurableBacklog = false

    /// Hard cap on the retry queue. Once reached, the oldest pending sample is
    /// dropped to make room for the newest. Production uses ~12 hours of
    /// significant-change/Visits ingestion; tests inject a smaller cap.
    private let retryQueueCapacity: Int

    private static let logger = WhereLog.location(LocationIngestorLog.self)

    init(
        store: any WhereStore,
        locationSource: any LocationSource,
        recordingDeviceID: RecordingDeviceID,
        calendar: Calendar,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
        retryQueueCapacity: Int = 1000,
        onPersisted: @escaping PostPersistHook,
    ) {
        precondition(retryQueueCapacity > 0, "retryQueueCapacity must be positive")
        self.store = store
        self.locationSource = locationSource
        self.recordingDeviceID = recordingDeviceID
        self.calendar = calendar
        self.outbox = outbox
        self.retryQueueCapacity = retryQueueCapacity
        self.onPersisted = onPersisted
    }

    deinit {
        ingestTask?.cancel()
        captureTask?.cancel()
        capturePersistTask?.cancel()
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
    public func start(effectiveAt: Date, dataEpochID: WhereDataEpochID) async throws {
        try await authorizeRecording(effectiveAt: effectiveAt, dataEpochID: dataEpochID)
        guard !isMonitoring else { return }
        isMonitoring = true
        await locationSource.start()
        Self.logger { .monitoringStarted }
        installIngestTaskIfNeeded()
    }

    /// Authorize automatic foreground samples without requiring background monitoring. Used
    /// when policy is On but authorization is only When-In-Use. Re-enabling also restores and
    /// drains the durable backlog before accepting a new foreground fix.
    public func authorizeRecording(
        effectiveAt: Date,
        dataEpochID: WhereDataEpochID,
    ) async throws {
        let currentEpochID: WhereDataEpochID
        do {
            currentEpochID = try await store.readSnapshot { try await (store.dataEpoch()).id }
        } catch {
            await closeRecordingAuthority()
            throw error
        }
        guard currentEpochID == dataEpochID else {
            await closeRecordingAuthority()
            throw RecordingPersistenceError.dataEpochChanged
        }
        guard acceptsSamples == false || authorizedDataEpochID != dataEpochID else { return }

        // Changing authority is fail-closed. In particular, if a remote reset
        // crosses backlog restoration/draining, the previous epoch must not
        // remain authorized while the replacement attempt fails.
        await closeRecordingAuthority()
        try await prepareRetryBacklog()
        let retained = retryQueue.filter { $0.dataEpochID == dataEpochID }
        if retained.count != retryQueue.count {
            retryQueue = retained
            await outbox.save(retryQueue)
        }
        // Flush anything that failed to persist before this session started,
        // before we (re)attach the stream consumer.
        let drainedDays = try await drainRetryQueue(expectedDataEpochID: dataEpochID)
        let confirmedEpochID = try await store.readSnapshot { try await (store.dataEpoch()).id }
        guard confirmedEpochID == dataEpochID else {
            throw RecordingPersistenceError.dataEpochChanged
        }
        authorizedDataEpochID = dataEpochID
        acceptsSamplesSince = effectiveAt
        acceptsSamples = true
        await Self.logger.measure(.postPersist, budget: .seconds(2)) {
            await onPersisted(IngestOutcome(
                changedDays: drainedDays,
                liveSample: nil,
                needsFullWidgetRebuild: !drainedDays.isEmpty,
            ))
        }
    }

    /// Load the durable retry sidecar without opening sample authority or draining it. Recording
    /// reconciliation calls this before persisting an acknowledgement, so an unreadable raw-
    /// location file leaves the device honestly pending and Off instead of claiming Recording.
    func prepareRetryBacklog() async throws {
        guard !didLoadDurableBacklog else { return }
        let restored = try await outbox.load()
        if !restored.isEmpty {
            Self.logger { .restoredBacklog(count: restored.count) }
        }
        // Rows written before device provenance existed intentionally remain unstamped and
        // legacy-visible. Re-attributing them to this installation would make them depend on
        // an assignment event that did not exist when they were captured.
        retryQueue = restored + retryQueue
        didLoadDurableBacklog = true
    }

    private func installIngestTaskIfNeeded() {
        guard ingestTask == nil else { return }
        let stream = locationSource.sampleStream
        ingestTask = Task { [weak self] in
            for await sample in stream {
                if Task.isCancelled { break }
                guard let self else { break }
                await ingest(sample)
                #if DEBUG
                    await recordTestingConsumption(of: sample.id)
                #endif
            }
        }
    }

    /// Revoke policy authority before acknowledging Off/unavailable. Late stream events and
    /// one-shot fixes are rejected, fix acquisition is cancelled, and any persist that already
    /// crossed the gate is awaited. The retry backlog is retained for a later re-enable;
    /// transactional destructive flows call ``pause()`` and discard only after commit.
    public func revokeRecordingAuthorization() async {
        // Consume the source even for an installation whose first policy is Off. Otherwise the
        // source's buffered callbacks can sit unobserved until a later On and cross the gate then.
        installIngestTaskIfNeeded()
        await closeRecordingAuthority()
        await capturePersistTask?.value
        await inFlightIngest?.value
    }

    /// Close the in-memory authority gate immediately. Unlike
    /// ``revokeRecordingAuthorization()``, this does not await in-flight
    /// persistence tasks and is therefore safe to call from one of those tasks
    /// when its expected epoch has just lost.
    private func closeRecordingAuthority(ifAuthorizedFor epochID: WhereDataEpochID? = nil) async {
        if let epochID, authorizedDataEpochID != epochID { return }
        acceptsSamples = false
        authorizedDataEpochID = nil
        acceptsSamplesSince = nil
        if isMonitoring {
            isMonitoring = false
            await locationSource.stop()
            Self.logger { .monitoringStopped }
        }
        captureTask?.cancel()
    }

    /// Reversibly pause ingestion while another operation temporarily owns the
    /// store. This closes the recording-authority gate, stops monitoring,
    /// cancels one-shot acquisition, and waits for persistence work that already
    /// crossed the gate. Both the in-memory retry queue and its durable outbox
    /// remain intact so a merge or rolled-back import can resume without losing
    /// samples captured during an earlier persistence outage.
    public func pause() async {
        await revokeRecordingAuthorization()
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
        Self.logger { .monitoringStopped }
    }

    /// Permanently discard samples awaiting persistence. The durable outbox is
    /// cleared before the in-memory queue: if durable deletion fails, the live
    /// process retains responsibility for retrying every sample.
    ///
    /// Call ``pause()`` first when the discard is part of a teardown, so no new
    /// sample can enter the queue while the durable clear is suspended.
    public func discardRetryBacklog() async throws {
        try await outbox.clear()
        retryQueue.removeAll()
    }

    /// Stop ingestion and guarantee nothing else writes until the next
    /// `start()`, then destructively discard both copies of the retry backlog.
    /// This primitive is for callers whose destructive operation cannot roll back. Reset and
    /// backup replacement instead compose ``pause()`` with a post-commit discard.
    ///
    /// Unlike ``pause()`` (a reversible pause that keeps the backlog),
    /// `quiesce()` clears it — the store is about to be erased, so those samples
    /// must not come back.
    public func quiesce() async throws {
        await pause()
        try await discardRetryBacklog()
        Self.logger { .quiesced }
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
    /// since it isn't a passive-tracking data point. The recording-authority gate
    /// is checked before acquisition and again before persistence, so a synced Off
    /// policy can revoke a fix already in flight.
    public func captureTodayIfNeeded(now: Date) {
        guard acceptsSamples, captureTask == nil else { return }
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
            Self.logger { .todayIntervalUnavailable }
            return
        }
        let interval = DateInterval(start: startOfDay, end: endOfDay)
        do {
            let existing = try await LocationHistoryReader(store: store).samples(in: interval)
            if existing.contains(where: {
                $0.source.isGPS
                    && ($0.recordingDeviceID == recordingDeviceID
                        || $0.recordingDeviceID == nil)
            }) { return }
        } catch {
            // Fail closed: if today's samples can't be read we skip rather than
            // risk logging a duplicate fix. Surfaced, not silently swallowed.
            Self.logger { .foregroundCaptureReadFailed(description: error.localizedDescription) }
            return
        }
        let fix = await Self.logger.measure(.acquireFix, budget: .seconds(10)) {
            await locationSource.requestCurrentLocation()
        }
        guard let sample = fix else { return }
        // The ~10s fix may have straddled a `pause()`; re-check the gate before
        // persisting, mirroring `ingest(_:)`. The guard and the `capturePersistTask`
        // assignment are synchronous (no `await` between), so a concurrent
        // `pause()` either sees `acceptsSamples == false` here (we skip) or sees
        // the handle already set (it awaits us) — never neither.
        guard !Task.isCancelled, accepts(sample) else { return }
        Self.logger { .capturedForegroundFix }
        // Persist via `processIngestedSample` on the capture's own handle rather
        // than `ingest(_:)`, so it never shares the stream loop's single
        // `inFlightIngest` slot. `pause()` awaits this handle independently.
        let work = Task { [weak self] in
            guard let self else { return }
            await processIngestedSample(sample)
        }
        capturePersistTask = work
        await work.value
        capturePersistTask = nil
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
    /// `pause()` (and before the next `start()`) is dropped rather than
    /// persisted, so a teardown that wipes the store can't be clobbered by a
    /// late GPS write. The persist is tracked in `inFlightIngest` so `pause()`
    /// can await it.
    private func ingest(_ sample: LocationSample) async {
        guard accepts(sample) else { return }
        let work = Task { [weak self] in
            guard let self else { return }
            await processIngestedSample(sample)
        }
        inFlightIngest = work
        await work.value
        inFlightIngest = nil
    }

    private func accepts(_ sample: LocationSample) -> Bool {
        guard acceptsSamples, let acceptsSamplesSince else { return false }
        return sample.timestamp >= acceptsSamplesSince
    }

    /// Persist one GPS-sourced sample, falling back to the retry queue on
    /// failure. Drains any backlog first so a single transient outage doesn't
    /// permanently reorder samples on disk.
    private func processIngestedSample(_ sample: LocationSample) async {
        guard let dataEpochID = authorizedDataEpochID else { return }
        let sample = sample.recorded(by: recordingDeviceID)
        do {
            let drainedDays = try await drainRetryQueue(expectedDataEpochID: dataEpochID)
            try await store.perform(expectedDataEpochID: dataEpochID) {
                try await store.add(sample: sample)
            }
            var changedDays = drainedDays
            changedDays.insert(calendar.startOfDay(for: sample.timestamp))
            await Self.logger.measure(.postPersist, budget: .seconds(2)) {
                await onPersisted(IngestOutcome(
                    changedDays: changedDays,
                    liveSample: sample,
                    needsFullWidgetRebuild: !drainedDays.isEmpty,
                ))
            }
        } catch RecordingPersistenceError.dataEpochChanged {
            // A reset/Replace revoked the authority this sample was admitted
            // under. Stop immediately and never put the known-stale sample into
            // the durable retry sidecar; reconciliation will reopen recording
            // only after resolving policy in the winning epoch.
            await closeRecordingAuthority(ifAuthorizedFor: dataEpochID)
        } catch {
            // Persistence failures (SwiftData save, CloudKit, etc.) are surfaced
            // via `os.Logger` rather than silently dropped. The stream keeps
            // running so a transient error doesn't stop tracking, and the sample
            // is queued for retry on the next save attempt.
            Self.logger(attachments: [.error(error, name: "persist-error")]) {
                .persistFailed(
                    sampleID: String(describing: sample.id),
                    description: error.localizedDescription,
                )
            }
            enqueueForRetry(LocationOutboxEntry(sample: sample, dataEpochID: dataEpochID))
            await outbox.save(retryQueue)
        }
    }

    private func enqueueForRetry(_ entry: LocationOutboxEntry) {
        if retryQueue.count >= retryQueueCapacity {
            Self.logger { .retryQueueAtCapacity(capacity: retryQueueCapacity) }
            retryQueue.removeFirst()
        }
        retryQueue.append(entry)
    }

    /// Try to flush every queued sample exactly once. Anything that still fails
    /// is re-queued at the tail; the next call gets the chance to retry it. The
    /// durable backlog is rewritten to match the post-drain queue.
    private func drainRetryQueue(
        expectedDataEpochID: WhereDataEpochID,
    ) async throws -> Set<Date> {
        // Spanned below the guard, so the common case — nothing queued, which is
        // every drain on a healthy device — records nothing at all.
        guard !retryQueue.isEmpty else { return [] }
        let pending = retryQueue
        retryQueue.removeAll(keepingCapacity: true)
        var persistedDays: Set<Date> = []
        var persistedSampleCount = 0
        var epochChanged = false
        await Self.logger.measure(.drainBacklog, budget: .seconds(5)) {
            for (index, entry) in pending.enumerated() {
                guard entry.dataEpochID == expectedDataEpochID else { continue }
                let sample = entry.sample
                do {
                    try await store.perform(expectedDataEpochID: entry.dataEpochID) {
                        try await store.add(sample: sample)
                    }
                    persistedSampleCount += 1
                    persistedDays.insert(calendar.startOfDay(for: sample.timestamp))
                } catch RecordingPersistenceError.dataEpochChanged {
                    enqueueForRetry(entry)
                    for remaining in pending.dropFirst(index + 1)
                        where remaining.dataEpochID == expectedDataEpochID
                    {
                        enqueueForRetry(remaining)
                    }
                    epochChanged = true
                    break
                } catch {
                    Self.logger(attachments: [.error(error, name: "retry-error")]) {
                        .retryStillFailing(
                            sampleID: String(describing: sample.id),
                            description: error.localizedDescription,
                        )
                    }
                    enqueueForRetry(entry)
                }
            }
        }
        if !persistedDays.isEmpty {
            Self.logger {
                .drainedBacklog(
                    sampleCount: persistedSampleCount,
                    dayCount: persistedDays.count,
                )
            }
        }
        await outbox.save(retryQueue)
        if epochChanged {
            throw RecordingPersistenceError.dataEpochChanged
        }
        return persistedDays
    }
}

#if DEBUG
    extension LocationIngestor {
        /// Test convenience for fixtures whose samples predate no meaningful policy cutoff.
        @_spi(Testing) public func start() async throws {
            let dataEpochID = try await (store.dataEpoch()).id
            try await start(effectiveAt: .distantPast, dataEpochID: dataEpochID)
        }

        /// Test convenience matching ``start()`` without activating background monitoring.
        @_spi(Testing) public func authorizeRecording() async throws {
            let dataEpochID = try await (store.dataEpoch()).id
            try await authorizeRecording(effectiveAt: .distantPast, dataEpochID: dataEpochID)
        }

        /// Enqueue a sample for retry without persisting. Tests use this to assert
        /// FIFO eviction at `retryQueueCapacity` without simulating hundreds of
        /// persistence failures.
        @_spi(Testing) public func testingEnqueueForRetry(
            _ sample: LocationSample,
            dataEpochID: WhereDataEpochID,
        ) {
            enqueueForRetry(LocationOutboxEntry(sample: sample, dataEpochID: dataEpochID))
        }

        /// Sample IDs currently in the retry queue, in FIFO order.
        @_spi(Testing) public func testingRetryQueueSampleIDs() -> [UUID] {
            retryQueue.map(\.sample.id)
        }

        /// Whether the automatic-sample authority gate is currently open.
        @_spi(Testing) public var testingIsAcceptingSamples: Bool {
            acceptsSamples
        }

        @_spi(Testing) public func testingHasConsumedSample(id: UUID) -> Bool {
            testingConsumedSampleIDs.contains(id)
        }

        private func recordTestingConsumption(of id: UUID) {
            testingConsumedSampleIDs.insert(id)
        }
    }
#endif
