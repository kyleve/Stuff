import Foundation
import Testing
@testable import WhereCore

/// Covers the freshness gate (`refreshIfStale`) and the hot-path change
/// detection (`publishAfterIngest`) the controller delegates every widget
/// publish to.
struct WidgetSnapshotPublisherTests {
    private actor SpyRefresher: WidgetTimelineRefreshing {
        private(set) var publishCount = 0
        private(set) var lastSnapshot: WidgetSnapshot?

        func publish(_ snapshot: WidgetSnapshot) async {
            publishCount += 1
            lastSnapshot = snapshot
        }
    }

    private static func makePublisher(
        now: @escaping @Sendable () -> Date,
        maxAge: TimeInterval = WidgetSnapshotPublisher.defaultMaxAge,
    ) throws -> (WidgetSnapshotPublisher, SwiftDataStore, SpyRefresher) {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = WidgetDataReader(store: store, aggregator: aggregator, attributor: .shared)
        let refresher = SpyRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            widgetRefresher: refresher,
            attributor: .shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
            maxAge: maxAge,
        )
        return (publisher, store, refresher)
    }

    @Test func publishBuildsAndPublishesASnapshot() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, _, refresher) = try Self.makePublisher(now: { now })
        await publisher.publish()
        #expect(await refresher.publishCount == 1)
    }

    @Test func refreshIfStaleSkipsWhenFresh() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, _, refresher) = try Self.makePublisher(now: { now })
        await publisher.publish()
        // Same day, within maxAge → no second publish.
        await publisher.refreshIfStale()
        #expect(await refresher.publishCount == 1)
    }

    @Test func refreshIfStaleRepublishesOncePastTheFreshnessWindow() async throws {
        let clock = TestClock(WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"))
        let (publisher, _, refresher) = try Self.makePublisher(now: { clock.now }, maxAge: 60)
        await publisher.publish()
        #expect(await refresher.publishCount == 1)

        clock.advance(by: 120) // same day, but older than the 60s window
        await publisher.refreshIfStale()
        #expect(await refresher.publishCount == 2)
    }

    @Test func publishAfterIngestSkipsWhenDayAndRegionUnchanged() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, store, refresher) = try Self.makePublisher(now: { now })
        let sf = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        try await store.perform { try await store.add(sample: sf) }
        await publisher.publish() // today now counts California
        #expect(await refresher.publishCount == 1)

        // A second California sample the same day can't change the snapshot.
        let sf2 = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 37.7750, longitude: -122.4195),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        await publisher.publishAfterIngest(of: sf2)
        #expect(await refresher.publishCount == 1)
    }

    @Test func publishAfterIngestRebuildsForANewRegion() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, store, refresher) = try Self.makePublisher(now: { now })
        let sf = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        try await store.perform { try await store.add(sample: sf) }
        await publisher.publish()
        #expect(await refresher.publishCount == 1)

        // A New York sample on the same day adds a region the snapshot lacks.
        let nyc = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        await publisher.publishAfterIngest(of: nyc)
        #expect(await refresher.publishCount == 2)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}
