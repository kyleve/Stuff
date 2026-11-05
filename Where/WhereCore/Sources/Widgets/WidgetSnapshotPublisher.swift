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
/// A cold launch or failed publication clears `lastPublished`, so the next refresh retries.
public actor WidgetSnapshotPublisher {
    private let widgetReader: any WidgetSnapshotReading
    private let widgetRefresher: any WidgetTimelineRefreshing
    private let attributor: any RegionAttributing
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let maxAge: TimeInterval

    private var lastPublished: PublishedWidgetSnapshot?
    private struct PublicationID: Hashable { let rawValue = UUID() }
    private var latestPublication: PublicationID?

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
        widgetReader: any WidgetSnapshotReading,
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
    /// than `maxAge`, or nothing published yet (cold launch) all fall through
    /// to a full rebuild.
    public func refreshIfStale() async {
        if let last = lastPublished {
            let today = CalendarDay(from: now(), in: calendar)
            let isFresh = now().timeIntervalSince(last.publishedAt) < maxAge
            if last.snapshot.day == today, isFresh {
                return
            }
        }
        await publish()
    }

    /// Publish the newest assessed result. A failed assessment withdraws stale counts and leaves
    /// the freshness gate open for recovery. A superseded build cannot erase a newer result.
    func publish() async {
        let publication = PublicationID()
        latestPublication = publication
        await Self.logger.measure(.publish, budget: .seconds(2)) {
            do {
                let snapshot = try await widgetReader.snapshot(asOf: now())
                guard latestPublication == publication else { return }
                try await widgetRefresher.publish(snapshot)
                guard latestPublication == publication else { return }
                lastPublished = PublishedWidgetSnapshot(snapshot: snapshot, publishedAt: now())
                Self.logger.published(day: .restricted(.dateTime, snapshot.day.iso8601))
            } catch {
                Self.logger.buildFailed(error: .restricted(.errorDetails, error))
                guard latestPublication == publication else { return }
                lastPublished = nil
                await widgetRefresher.withdraw()
            }
        }
    }

    /// Only foundation-contract GPS has the old additive same-day guarantee. Recording evidence
    /// can change source selection elsewhere, including when this point repeats an existing region.
    func publishAfterIngest(of sample: LocationSample) async {
        if let last = lastPublished, let assessment = last.snapshot.assessment,
           assessment.version.major == 0,
           case let .complete(regions) = assessment.dayRegions
        {
            let day = CalendarDay(from: sample.timestamp, in: calendar)
            let region = attributor.region(at: sample.coordinate)
            if day == last.snapshot.day, regions.contains(region) { return }
        }
        await publish()
    }
}
