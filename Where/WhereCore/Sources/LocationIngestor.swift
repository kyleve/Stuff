import Foundation
import os

/// Owns live GPS ingestion: the location-monitoring lifecycle, the
/// single-consumer sample stream, the retry queue that survives transient
/// persistence failures, and authorization. Persisted samples are reported back
/// through an injected post-persist hook, so this actor stays unaware of
/// reminders and widgets — the assembler wires those in.
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

    private var ingestTask: Task<Void, Never>?

    /// Whether the underlying location monitoring is currently active. Tracked
    /// separately from `ingestTask` because the ingestion task outlives a
    /// `stop()` pause (see `start()` for why).
    private var isMonitoring = false

    /// Samples whose persist call failed (e.g. transient SwiftData / CloudKit
    /// error). Drained before each new GPS save and on the next `start()` so a
    /// brief I/O outage doesn't silently drop measurements.
    private var retryQueue: [LocationSample] = []

    /// Hard cap on the retry queue. Once reached, the oldest pending sample is
    /// dropped to make room for the newest. Sized to ~12 hours of
    /// significant-change/Visits ingestion, so reaching the cap means something
    /// is very wrong with persistence and we'd rather keep recent than ancient.
    private static let retryQueueCapacity = 1000

    private static let logger = Logger(
        subsystem: "com.stuff.where",
        category: "LocationIngestor",
    )

    init(
        store: any WhereStore,
        locationSource: any LocationSource,
        calendar: Calendar,
        onPersisted: @escaping PostPersistHook,
    ) {
        self.store = store
        self.locationSource = locationSource
        self.calendar = calendar
        self.onPersisted = onPersisted
    }

    deinit {
        ingestTask?.cancel()
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
        guard !isMonitoring else { return }
        isMonitoring = true
        await locationSource.start()
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
                await processIngestedSample(sample)
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

    /// The current location authorization status.
    public func authorizationStatus() async -> LocationAuthorizationStatus {
        await locationSource.currentAuthorization()
    }

    /// Live stream of authorization-status changes (system prompt results and
    /// Settings-app changes). Subscribe once and iterate.
    public func authorizationUpdates() -> AsyncStream<LocationAuthorizationStatus> {
        locationSource.authorizationUpdates
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

    /// Try to flush every queued sample exactly once. Anything that still fails
    /// is re-queued at the tail; the next call gets the chance to retry it.
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
                    "Retry still failing for GPS sample \(sample.id, privacy: .public): \(error.localizedDescription, privacy: .public)",
                )
                enqueueForRetry(sample)
            }
        }
        return persistedDays
    }
}
