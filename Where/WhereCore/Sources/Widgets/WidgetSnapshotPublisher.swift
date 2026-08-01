import Foundation
import PeriscopeCore
import RegionKit

/// Owns the published widget snapshot and the policy for when to rebuild it.
///
/// The widget extension only ever reads the published App Group file, so the
/// app has to republish whenever what a widget shows could have changed. This
/// actor keeps the last published snapshot in memory so it can:
/// - skip needless rebuilds + WidgetKit reloads on the hot GPS path
///   (`publishAfterIngest(of:)`, exact change-detection), and
/// - throttle passive launch/activation refreshes (`refreshIfStale()`, a
///   freshness gate),
/// while `publish()` unconditionally rebuilds after a committed mutation.
///
/// `lastPublished` is only `nil` on a cold launch (a fresh instance), which is
/// exactly when one publish is desirable to recover from any staleness.
public actor WidgetSnapshotPublisher {
    private let widgetReader: WidgetDataReader
    private let widgetRefresher: any WidgetTimelineRefreshing
    private let attributor: any RegionAttributing
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let maxAge: TimeInterval

    private var lastPublished: PublishedWidgetSnapshot?
    private var pendingPublishTask: Task<Void, Never>?
    private var publishRequested = false
    private var retryFailedPublish = false
    private var externalChangesTask: Task<Void, Never>?
    #if DEBUG
        private var receivedPublishRequestCount = 0
    #endif

    private struct PublishedWidgetSnapshot {
        let snapshot: WidgetSnapshot
        let publishedAt: Date
    }

    /// Maximum age of the published snapshot before a passive launch/activation
    /// refresh rebuilds it on the same calendar day. The high-frequency GPS path
    /// bypasses this via exact change-detection; this only throttles
    /// `refreshIfStale()` so frequent foregrounding doesn't needlessly re-pull
    /// the store and reload widgets.
    static let defaultMaxAge: TimeInterval = 3 * 60 * 60

    private static let logger = WhereLog.widgets(WidgetSnapshotPublisherLog.self)

    init(
        widgetReader: WidgetDataReader,
        widgetRefresher: any WidgetTimelineRefreshing,
        attributor: any RegionAttributing,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        maxAge: TimeInterval = WidgetSnapshotPublisher.defaultMaxAge,
    ) {
        self.widgetReader = widgetReader
        self.widgetRefresher = widgetRefresher
        self.attributor = attributor
        self.calendar = calendar
        self.now = now
        self.maxAge = maxAge
    }

    /// Recompute and publish the snapshot from whatever the store currently
    /// holds, without needing a mutation first, but skip the rebuild when a
    /// current-day snapshot was published recently. A new day, a snapshot older
    /// than `maxAge`, or nothing published yet (cold launch) all fall through to
    /// a full rebuild.
    public func refreshIfStale() async {
        if retryFailedPublish == false, let last = lastPublished {
            let today = calendar.startOfDay(for: now())
            let isFresh = now().timeIntervalSince(last.publishedAt) < maxAge
            if last.snapshot.day == today, isFresh {
                return
            }
        }
        await publish()
    }

    /// Recompute today's `WidgetSnapshot` from the store and hand it to the
    /// refresher to publish + reload. Concurrent callers join one task; a call
    /// arriving while that task is publishing coalesces into one final rebuild
    /// so the artifact includes the latest committed store state.
    ///
    /// A failure here is non-fatal: the widget keeps showing its last published
    /// snapshot, and the failed result is never cached as fresh.
    func publish() async {
        #if DEBUG
            receivedPublishRequestCount += 1
        #endif
        if let pendingPublishTask {
            publishRequested = true
            await pendingPublishTask.value
            return
        }

        publishRequested = true
        let task = Task {
            await self.drainPublishRequests()
        }
        pendingPublishTask = task
        await task.value
    }

    /// Rebuild after every store change imported from another process or
    /// device. `beforePublishing` refreshes any live derived dependencies from
    /// that same store state before the snapshot reads them. Local writes do not
    /// enter this stream: their journal/ingestor paths already invoke the exact
    /// publish operation they need.
    func startObservingExternalChanges(
        _ changes: AsyncStream<Void>,
        beforePublishing: @escaping @Sendable () async -> Void,
    ) {
        precondition(
            externalChangesTask == nil,
            "WidgetSnapshotPublisher external observation started twice",
        )
        externalChangesTask = Task { [weak self] in
            for await _ in changes {
                guard Task.isCancelled == false else { return }
                await beforePublishing()
                guard Task.isCancelled == false else { return }
                await self?.publish()
            }
        }
    }

    /// Stop the remote-import observer. Scope teardown normally reaches this
    /// through `deinit`; the explicit pair also makes lifecycle tests and a
    /// deliberate restart unambiguous.
    func stopObservingExternalChanges() async {
        let task = externalChangesTask
        task?.cancel()
        await task?.value
        externalChangesTask = nil
    }

    deinit {
        externalChangesTask?.cancel()
    }

    #if DEBUG
        /// Number of calls received by this instance. Test-only visibility lets
        /// a concurrency test establish that every caller joined the in-flight
        /// task before releasing its controlled sink.
        @_spi(Testing) public var testingReceivedPublishRequestCount: Int {
            receivedPublishRequestCount
        }
    #endif

    private func drainPublishRequests() async {
        repeat {
            publishRequested = false
            await performPublish()
        } while publishRequested
        pendingPublishTask = nil
    }

    private func performPublish() async {
        await Self.logger.measure(.publish, budget: .seconds(2)) {
            do {
                let generatedAt = now()
                let snapshot = try await widgetReader.snapshot(asOf: generatedAt)
                try await widgetRefresher.publish(snapshot)
                lastPublished = PublishedWidgetSnapshot(
                    snapshot: snapshot,
                    publishedAt: generatedAt,
                )
                retryFailedPublish = false
                Self.logger {
                    .published(
                        day: dayLogLabel(snapshot.day),
                        regionCount: snapshot.dayRegions.count,
                    )
                }
            } catch {
                retryFailedPublish = true
                Self.logger { .buildFailed(description: error.localizedDescription) }
            }
        }
    }

    /// Publish after a single ingested sample, skipping the rebuild + WidgetKit
    /// reload when the sample provably can't change what the widgets show: it
    /// falls on the same calendar day as the last published snapshot *and*
    /// resolves to a region that day already counts. Anything else — a new
    /// region for the day, a sample on a different day, or no prior snapshot —
    /// does a full rebuild. (A GPS sample is timestamped ~now, so it can only
    /// add to its own day; a region already present means the day's regions and
    /// the year totals are both unchanged.)
    func publishAfterIngest(of sample: LocationSample) async {
        if retryFailedPublish == false, let last = lastPublished {
            let day = calendar.startOfDay(for: sample.timestamp)
            let region = attributor.region(at: sample.coordinate)
            if day == last.snapshot.day, last.snapshot.dayRegions.contains(region) {
                return
            }
        }
        await publish()
    }

    private func dayLogLabel(_ day: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
        )
    }
}
