import Foundation
import RegionKit
import SwiftData
import Testing
@testable import WhereCore

/// Covers the freshness gate (`refreshIfStale`) and the hot-path change
/// detection (`publishAfterIngest`) the controller delegates every widget
/// publish to.
struct WidgetSnapshotPublisherTests {
    private actor SpyRefresher: WidgetTimelineRefreshing {
        private(set) var publishCount = 0
        private(set) var lastSnapshot: WidgetSnapshot?

        private(set) var withdrawCount = 0
        func withdraw() async {
            withdrawCount += 1
            lastSnapshot = nil
        }

        private var failsNextPublish = false
        func failNextPublish() {
            failsNextPublish = true
        }

        func publish(_ snapshot: WidgetSnapshot, access _: DataCompatibilityAccess?) async throws {
            if failsNextPublish {
                failsNextPublish = false
                throw WidgetPublisherReadFixture.Failure.read
            }
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
        let reader = WidgetDataReader(
            store: store,
            history: LocationHistoryReader(
                store: store,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
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

    @Test(arguments: [false, true]) func supersededBuildCannotReplaceOrWithdrawNewerPublication(
        fails: Bool,
    ) async throws {
        let gate = CompatibilityTestGate()
        let reader = WidgetPublisherReadFixture(gate: gate, firstFails: fails)
        let refresher = SpyRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            widgetRefresher: refresher,
            attributor: RegionAttributor.shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: { WhereCoreTestSupport.iso("2026-03-15T12:00:00Z") },
        )
        let older = Task { await publisher.publish() }
        await gate.waitUntilEntered()
        await publisher.publish()
        let newer = try #require(await refresher.lastSnapshot)
        await gate.resume()
        await older.value
        #expect(await refresher.lastSnapshot == newer)
        #expect(await refresher.publishCount == 1)
        #expect(await refresher.withdrawCount == 0)
    }

    @Test func repeatedRegionUnderRecordingPolicyStillReassesses() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let date = Date(timeIntervalSinceReferenceDate: 7200)
        let history = LocationHistoryReaderTestSupport.reader(store)
        let reader = WidgetDataReader(
            store: store,
            history: history,
            aggregator: DayAggregator(
                calendar: LocationHistoryReaderTestSupport.calendar,
                timeZone: LocationHistoryReaderTestSupport.calendar.timeZone,
            ),
        )
        let refresher = SpyRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            widgetRefresher: refresher,
            attributor: RegionAttributor.shared,
            calendar: LocationHistoryReaderTestSupport.calendar,
            now: { date },
        )
        let sample = try LocationHistoryReaderTestSupport.sample(seconds: 7200)
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        await publisher.publish()
        #expect(await refresher.lastSnapshot?.assessment?.dayRegions == .complete([.california]))
        let competing = try LocationHistoryReaderTestSupport.competingTracks()
        try await LocationHistoryReaderTestSupport.add(competing, to: store)
        // Even a repeated California point must reassess the newly arrived competing history.
        await publisher.publishAfterIngest(of: sample)
        #expect(await refresher.publishCount == 2)
        #expect(await refresher.lastSnapshot?.assessment?.dayRegions == .needsReview)
    }

    @Test func failedFilePublicationWithdrawsPriorCountsAndRetriesThroughCompatibilityQueue(
    ) async throws {
        let access = try CompatibilityOutputTestSupport.access()
        let reader = WidgetDataReader(
            store: access.store,
            history: LocationHistoryReader(
                store: access.store,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
        )
        let refresher = SpyRefresher()
        let outputs = DataCompatibilityOutputs(
            access: access,
            reminders: NoopEveningReminderScheduler(),
            summary: NoopDailySummaryScheduler(),
            widgets: refresher,
        )
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            widgetRefresher: outputs.widgets,
            attributor: RegionAttributor.shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: { WhereCoreTestSupport.iso("2026-03-15T12:00:00Z") },
        )
        await publisher.publish()
        #expect(await refresher.lastSnapshot != nil)
        await refresher.failNextPublish()
        await publisher.publish()
        #expect(await refresher.lastSnapshot == nil)
        #expect(await refresher.withdrawCount == 1)
        await publisher.refreshIfStale()
        #expect(await refresher.lastSnapshot != nil)
        #expect(await refresher.publishCount == 2)
    }

    @Test func publishBuildsAndPublishesASnapshot() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, _, refresher) = try Self.makePublisher(now: { now })
        await publisher.publish()
        #expect(await refresher.publishCount == 1)
    }

    @Test func incompleteDestructiveGenerationWithdrawsCountsAndKeepsRecoveryEligible(
    ) async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = WidgetDataReader(
            store: store,
            history: LocationHistoryReader(
                store: store,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
        )
        let refresher = SpyRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            widgetRefresher: refresher,
            attributor: RegionAttributor.shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: { now },
        )
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: now,
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 5,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
        }
        await publisher.publish()
        #expect(await refresher.lastSnapshot?.assessment?.dayRegions == .complete([.california]))

        // CloudKit can deliver a later destructive event before its parent. Once the store
        // knows that history may have been erased, the widget must stop showing the prior data.
        let remoteContext = ModelContext(container)
        remoteContext.insert(SDWhereDataGeneration(value: WhereDataGeneration(
            id: WhereDataGenerationID(rawValue: UUID()),
            parentIDs: [.initial],
            revision: 2,
            changedAt: now.addingTimeInterval(1),
            changedByDeviceID: RecordingDeviceID(rawValue: UUID()),
            reason: .accountReset,
        )))
        try remoteContext.save()

        await publisher.publish()

        #expect(await refresher.publishCount == 1)
        #expect(await refresher.withdrawCount == 1)
        #expect(await refresher.lastSnapshot == nil)
        await publisher.refreshIfStale()
        #expect(await refresher.withdrawCount == 2)
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
            recordingDay: nil,
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
            recordingDay: nil,
        )
        // Live ingestion stamps this context even under the foundation contract.
        let stamped = sf2.recorded(by: .init(rawValue: UUID()))
        #expect(stamped.recordingDay == .unresolved)
        await publisher.publishAfterIngest(of: stamped)
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
            recordingDay: nil,
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
            recordingDay: nil,
        )
        await publisher.publishAfterIngest(of: nyc)
        #expect(await refresher.publishCount == 2)
    }
}
