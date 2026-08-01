import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the freshness gate (`refreshIfStale`) and the hot-path change
/// detection (`publishAfterIngest`) the controller delegates every widget
/// publish to.
struct WidgetSnapshotPublisherTests {
    private actor SpyRefresher: WidgetTimelineRefreshing {
        private(set) var publishCount = 0
        private(set) var lastSnapshot: WidgetSnapshot?

        func publish(_ snapshot: WidgetSnapshot) async throws {
            publishCount += 1
            lastSnapshot = snapshot
        }
    }

    private actor ControllableRefresher: WidgetTimelineRefreshing {
        struct Failure: Error {}

        private(set) var publishCount = 0
        private var shouldFailNextPublish = false

        func failNextPublish() {
            shouldFailNextPublish = true
        }

        func publish(_: WidgetSnapshot) async throws {
            publishCount += 1
            if shouldFailNextPublish {
                shouldFailNextPublish = false
                throw Failure()
            }
        }
    }

    private actor GatedRefresher: WidgetTimelineRefreshing {
        private var firstPublishContinuation: CheckedContinuation<Void, Never>?
        private(set) var publishCount = 0

        var isFirstPublishSuspended: Bool {
            firstPublishContinuation != nil
        }

        func publish(_: WidgetSnapshot) async throws {
            publishCount += 1
            guard publishCount == 1 else { return }
            await withCheckedContinuation { continuation in
                firstPublishContinuation = continuation
            }
        }

        func resumeFirstPublish() {
            firstPublishContinuation?.resume()
            firstPublishContinuation = nil
        }
    }

    private actor GatedExternalPreparation {
        private var continuation: CheckedContinuation<Void, Never>?

        var isWaiting: Bool {
            continuation != nil
        }

        func prepare() async {
            await withTaskCancellationHandler {
                guard Task.isCancelled == false else { return }
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                }
            } onCancel: {
                Task { await self.resume() }
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    private struct WaitTimeout: Error {}

    private static func makePublisher(
        now: @escaping @Sendable () -> Date,
        maxAge: TimeInterval = WidgetSnapshotPublisher.defaultMaxAge,
    ) throws -> (WidgetSnapshotPublisher, SwiftDataStore, SpyRefresher) {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = WidgetDataReader(
            store: store,
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
        )
        let refresher = SpyRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            widgetRefresher: refresher,
            attributor: RegionAttributor.shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
            maxAge: maxAge,
        )
        return (publisher, store, refresher)
    }

    private static func makePublisher(
        now: @escaping @Sendable () -> Date,
        refresher: any WidgetTimelineRefreshing,
    ) throws -> WidgetSnapshotPublisher {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        return WidgetSnapshotPublisher(
            widgetReader: WidgetDataReader(
                store: store,
                aggregator: aggregator,
                attributor: RegionAttributor.shared,
            ),
            widgetRefresher: refresher,
            attributor: RegionAttributor.shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
        )
    }

    private static func waitUntil(
        _ predicate: @escaping @Sendable () async -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while await predicate() == false {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw WaitTimeout() }
            await Task.yield()
        }
    }

    @Test func publishBuildsAndPublishesASnapshot() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, _, refresher) = try Self.makePublisher(now: { now })
        await publisher.publish()
        #expect(await refresher.publishCount == 1)
        #expect(await refresher.lastSnapshot?.generatedAt == now)
        #expect(await refresher.lastSnapshot?.surface != nil)
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
        let clock = MutableClock(WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"))
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

    @Test func aFailedWriteIsNotCachedAsFresh() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let refresher = ControllableRefresher()
        let publisher = try Self.makePublisher(now: { now }, refresher: refresher)

        await refresher.failNextPublish()
        await publisher.publish()
        #expect(await refresher.publishCount == 1)

        await publisher.refreshIfStale()
        #expect(await refresher.publishCount == 2)

        await publisher.refreshIfStale()
        #expect(await refresher.publishCount == 2)
    }

    @Test func failureAfterASuccessInvalidatesTheFreshnessGate() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let refresher = ControllableRefresher()
        let publisher = try Self.makePublisher(now: { now }, refresher: refresher)

        await publisher.publish()
        await refresher.failNextPublish()
        await publisher.publish()
        #expect(await refresher.publishCount == 2)

        // The earlier successful snapshot is still young, but it predates the
        // failed mutation publish and therefore must not suppress this retry.
        await publisher.refreshIfStale()
        #expect(await refresher.publishCount == 3)

        await publisher.refreshIfStale()
        #expect(await refresher.publishCount == 3)
    }

    @Test func failureAfterASuccessInvalidatesTheIngestFastPath() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let refresher = ControllableRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: WidgetDataReader(
                store: store,
                aggregator: aggregator,
                attributor: RegionAttributor.shared,
            ),
            widgetRefresher: refresher,
            attributor: RegionAttributor.shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: { now },
        )
        let sample = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
        try await store.perform { try await store.add(sample: sample) }
        await publisher.publish()

        await refresher.failNextPublish()
        await publisher.publish()
        #expect(await refresher.publishCount == 2)

        // Even though this sample's day and region match the last good
        // snapshot, the intervening failed rebuild means that snapshot may no
        // longer represent other store changes.
        await publisher.publishAfterIngest(of: sample)
        #expect(await refresher.publishCount == 3)
    }

    @Test func anExternalChangeTriggersAFullPublish() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, _, refresher) = try Self.makePublisher(now: { now })
        let changes = StoreChangeBroadcaster()
        let preparation = GatedExternalPreparation()

        await publisher.startObservingExternalChanges(
            changes.subscribe(),
            beforePublishing: { await preparation.prepare() },
        )
        changes.send()

        try await Self.waitUntil { await preparation.isWaiting }
        #expect(await refresher.publishCount == 0)
        await preparation.resume()
        try await Self.waitUntil { await refresher.publishCount == 1 }
        await publisher.stopObservingExternalChanges()
    }

    @Test func stoppingExternalObservationDuringPreparationSkipsThePublish() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, _, refresher) = try Self.makePublisher(now: { now })
        let changes = StoreChangeBroadcaster()
        let preparation = GatedExternalPreparation()

        await publisher.startObservingExternalChanges(
            changes.subscribe(),
            beforePublishing: { await preparation.prepare() },
        )
        changes.send()
        try await Self.waitUntil { await preparation.isWaiting }

        await publisher.stopObservingExternalChanges()
        #expect(await publisher.testingReceivedPublishRequestCount == 0)
        #expect(await refresher.publishCount == 0)
    }

    @Test func concurrentRequestsCoalesceIntoOneFinalRebuild() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let refresher = GatedRefresher()
        let publisher = try Self.makePublisher(now: { now }, refresher: refresher)

        let first = Task { await publisher.publish() }
        try await Self.waitUntil { await refresher.isFirstPublishSuspended }

        let joined = (0 ..< 5).map { _ in
            Task { await publisher.publish() }
        }
        try await Self.waitUntil {
            await publisher.testingReceivedPublishRequestCount == 6
        }
        await refresher.resumeFirstPublish()

        await first.value
        for task in joined {
            await task.value
        }
        #expect(await refresher.publishCount == 2)
    }
}
