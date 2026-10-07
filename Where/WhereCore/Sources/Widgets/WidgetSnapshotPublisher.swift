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
/// A cold launch, failed publication, or output withdrawal invalidates the
/// cached publication, so the next permitted refresh rebuilds the snapshot.
public actor WidgetSnapshotPublisher {
    private let widgetReader: WidgetDataReader
    private let outputs: DataCompatibilityOutputs
    private let attributor: any RegionAttributing
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let maxAge: TimeInterval

    private var lastPublished: PublishedWidgetSnapshot?
    private var cacheRevision = UUID()

    private struct PublishedWidgetSnapshot {
        let snapshot: WidgetSnapshot
        let publishedAt: Date
        let withdrawalRevision: DataCompatibilityOutputs.WithdrawalRevision
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
        outputs: DataCompatibilityOutputs,
        attributor: any RegionAttributing,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        maxAge: TimeInterval = WidgetSnapshotPublisher.defaultMaxAge,
    ) {
        self.widgetReader = widgetReader
        self.outputs = outputs
        self.attributor = attributor
        self.calendar = calendar
        self.now = now
        self.maxAge = maxAge
    }

    /// Withdrawn outputs must be rebuilt after recovery, including when an older publish resumes.
    func invalidate() {
        cacheRevision = UUID()
        lastPublished = nil
    }

    /// Recompute and publish the snapshot from whatever the store currently
    /// holds, without needing a mutation first, but skip the rebuild when a
    /// current-day snapshot was published recently. A new day, a snapshot older
    /// than `maxAge`, or nothing published yet (cold launch) all fall through
    /// to a full rebuild.
    public func refreshIfStale() async {
        guard await hasDataAccess() else { return }
        if let last = await currentPublication() {
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
    /// can change what a widget shows. Failed publication is logged and retried
    /// on the next refresh. Compatibility failures withdraw cached content.
    func publish() async {
        let revision = cacheRevision
        let withdrawalRevision = await outputs.withdrawalRevision
        guard await hasDataAccess() else { return }
        await Self.logger.measure(.publish, budget: .seconds(2)) {
            do {
                let snapshot = try await widgetReader.snapshot(asOf: now())
                try await outputs.widgets.publish(snapshot)
                guard await hasDataAccess() else { return }
                guard await outputs.withdrawalRevision == withdrawalRevision else { return }
                guard revision == cacheRevision else { return }
                lastPublished = PublishedWidgetSnapshot(
                    snapshot: snapshot,
                    publishedAt: now(),
                    withdrawalRevision: withdrawalRevision,
                )
                Self.logger {
                    .published(
                        day: dayLogLabel(snapshot.day),
                        regionCount: snapshot.dayRegions.count,
                    )
                }
            } catch let error as DataCompatibilityError {
                invalidate()
                _ = await hasDataAccess()
                Self.logger { .buildFailed(description: error.localizedDescription) }
            } catch let error as RecordingPersistenceError {
                // Generation/policy gaps mean a destructive CloudKit change may already be known
                // even
                // though its complete rows have not arrived. Keeping the last good snapshot would
                // continue exposing history the user erased, so publish an honest empty value
                // until a later remote-change reconcile can build the new generation.
                let date = now()
                let snapshot = WidgetSnapshot(
                    day: calendar.startOfDay(for: date),
                    year: CalendarDay(from: date, in: calendar).year,
                    dayRegions: [],
                    totals: [:],
                )
                do {
                    try await outputs.widgets.publish(snapshot)
                    guard await hasDataAccess() else { return }
                    guard await outputs.withdrawalRevision == withdrawalRevision else { return }
                    guard revision == cacheRevision else { return }
                    lastPublished = PublishedWidgetSnapshot(
                        snapshot: snapshot,
                        publishedAt: date,
                        withdrawalRevision: withdrawalRevision,
                    )
                } catch {
                    invalidate()
                    Self.logger { .buildFailed(description: error.localizedDescription) }
                }
                Self.logger { .buildFailed(description: error.localizedDescription) }
            } catch {
                invalidate()
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
        guard await hasDataAccess() else { return }
        if let last = await currentPublication() {
            let day = calendar.startOfDay(for: sample.timestamp)
            let region = attributor.region(at: sample.coordinate)
            if day == last.snapshot.day, last.snapshot.dayRegions.contains(region) {
                return
            }
        }
        await publish()
    }

    private func currentPublication() async -> PublishedWidgetSnapshot? {
        let withdrawalRevision = await outputs.withdrawalRevision
        guard lastPublished?.withdrawalRevision == withdrawalRevision else { return nil }
        return lastPublished
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

    private func hasDataAccess() async -> Bool {
        do {
            try await widgetReader.requireDataAccess()
            return true
        } catch {
            invalidate()
            await outputs.withdraw()
            Self.logger { .buildFailed(description: error.localizedDescription) }
            return false
        }
    }
}
