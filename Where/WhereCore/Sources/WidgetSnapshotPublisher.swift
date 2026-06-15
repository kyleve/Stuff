import Foundation
import os

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
    private let attributor: RegionAttributor
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let maxAge: TimeInterval

    private var lastPublished: PublishedWidgetSnapshot?

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

    private static let logger = Logger(
        subsystem: "com.stuff.where",
        category: "WidgetSnapshotPublisher",
    )

    init(
        widgetReader: WidgetDataReader,
        widgetRefresher: any WidgetTimelineRefreshing,
        attributor: RegionAttributor,
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
        if let last = lastPublished {
            let today = calendar.startOfDay(for: now())
            let isFresh = now().timeIntervalSince(last.publishedAt) < maxAge
            if last.snapshot.day == today, isFresh {
                return
            }
        }
        await publish()
    }

    /// Recompute today's `WidgetSnapshot` from the store and hand it to the
    /// refresher to publish + reload. Called after every committed mutation that
    /// can change what a widget shows. A failure here is non-fatal: the widget
    /// keeps showing its last published snapshot.
    func publish() async {
        do {
            let snapshot = try await widgetReader.snapshot(asOf: now())
            await widgetRefresher.publish(snapshot)
            lastPublished = PublishedWidgetSnapshot(snapshot: snapshot, publishedAt: now())
        } catch {
            Self.logger.error(
                "Failed to build widget snapshot: \(error.localizedDescription, privacy: .public)",
            )
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
        if let last = lastPublished {
            let day = calendar.startOfDay(for: sample.timestamp)
            let region = attributor.region(at: sample.coordinate)
            if day == last.snapshot.day, last.snapshot.dayRegions.contains(region) {
                return
            }
        }
        await publish()
    }
}
