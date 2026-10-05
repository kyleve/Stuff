import Foundation
import RegionKit
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the freshness gate (`refreshIfStale`) and the hot-path change
/// detection (`publishAfterIngest`) the controller delegates every widget
/// publish to.
struct WidgetSnapshotPublisherTests {
    private actor SpyRefresher: WidgetTimelineRefreshing {
        func publishCompatibility(_: WidgetCompatibilitySnapshot) async {}
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
        let reader = WidgetDataReader(
            store: store,
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
        )
        let refresher = SpyRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            outputs: CompatibilityOutputTestSupport.makeOutputs(
                store: store,
                widgetRefresher: refresher,
            ),
            attributor: RegionAttributor.shared,
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

    @Test func incompleteDestructiveGenerationReplacesSensitiveSnapshotWithEmptyState(
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
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
        )
        let refresher = SpyRefresher()
        let publisher = WidgetSnapshotPublisher(
            widgetReader: reader,
            outputs: CompatibilityOutputTestSupport.makeOutputs(
                store: store,
                widgetRefresher: refresher,
            ),
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
            ))
        }
        await publisher.publish()
        #expect(await refresher.lastSnapshot?.dayRegions == [.california])

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

        #expect(await refresher.publishCount == 2)
        #expect(await refresher.lastSnapshot?.dayRegions.isEmpty == true)
        #expect(await refresher.lastSnapshot?.totals.isEmpty == true)
    }

    @Test func refreshIfStaleSkipsWhenFresh() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (publisher, _, refresher) = try Self.makePublisher(now: { now })
        await publisher.publish()
        // Same day, within maxAge → no second publish.
        await publisher.refreshIfStale()
        #expect(await refresher.publishCount == 1)
    }

    @Test func invalidationPreventsAnInFlightPublicationFromRestoringFreshness() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let services = WhereServices(
            store: world.store,
            compatibilityServices: world.services,
            locationSource: ScriptedLocationSource(),
            now: { now },
        )
        let gate = CompatibilityOutputTestSupport.Gate()
        await world.widgets.holdNextPublication(gate)
        let publication = Task { await services.widgets.publish() }
        await gate.waitUntilEntered()
        await services.widgets.invalidate()
        gate.resume()
        await publication.value

        await services.widgets.refreshIfStale()

        #expect(await world.widgets.snapshots.count == 2)
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

    enum WithdrawalTrigger: CaseIterable {
        case explicit, failedWithdrawal, notification, authorization, widgetPublication
    }

    enum RefreshTrigger: CaseIterable {
        case foreground, sameRegionIngest
    }

    @Test(arguments: WithdrawalTrigger.allCases, RefreshTrigger.allCases)
    func withdrawnSnapshotRepublishesAfterRecovery(
        withdrawal: WithdrawalTrigger,
        refresh: RefreshTrigger,
    ) async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let services = WhereServices(
            store: world.store,
            compatibilityServices: world.services,
            locationSource: ScriptedLocationSource(),
            now: { now },
        )
        let sample = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
        try await world.store.perform { try await world.store.add(sample: sample) }
        await services.widgets.publish()
        #expect(await world.widgets.snapshots.count == 1)
        #expect(await world.widgets.snapshots.last?.dayRegions == [.california])

        switch withdrawal {
            case .explicit:
                await world.services.outputs.withdraw()
            case .failedWithdrawal:
                await world.widgets.failNextCompatibilityPublication(
                    with: DataCompatibilityError
                        .verificationFailed(description: "Injected failure"),
                )
                await world.services.outputs.withdraw()
            case .notification, .authorization:
                try await CompatibilityOutputTestSupport.makeIncompatible(world.store)
                if withdrawal == .notification {
                    await world.services.outputs.summary.reconcile(
                        enabled: true,
                        time: .defaultMorning,
                        body: "summary",
                    )
                } else {
                    #expect(await !world.services.outputs.summary.requestAuthorization())
                }
                await world.store.setSupportedDataCompatibilityVersionForTesting(
                    CompatibilityTestSupport.nextVersion,
                )
            case .widgetPublication:
                await world.widgets.failNextPublication(
                    with: DataCompatibilityError
                        .verificationFailed(description: "Injected failure"),
                )
                await services.widgets.publish()
        }
        #expect(await world.widgets.snapshots.count == 1)
        if withdrawal != .failedWithdrawal {
            #expect(await world.widgets.compatibility.last?.allowsData == false)
        }
        // Recovery is deliberately independent of the UI observer and runtime suspension.
        let recoveredStatus = try await world.services.coordinator.status()
        try recoveredStatus.requireAccess()
        switch refresh {
            case .foreground: await services.widgets.refreshIfStale()
            case .sameRegionIngest: await services.widgets.publishAfterIngest(of: sample)
        }
        #expect(await world.widgets.snapshots.count == 2)
        #expect(await world.widgets.snapshots.last?.dayRegions == [.california])
        #expect(await world.widgets.compatibility.last?.requiredVersion == recoveredStatus
            .requiredVersion)

        // The new publication is fresh; recovery must not disable ordinary throttling.
        await services.widgets.refreshIfStale()
        await services.widgets.publishAfterIngest(of: sample)
        #expect(await world.widgets.snapshots.count == 2)
    }

    @Test func withdrawalDuringPublicationCannotRestoreFreshness() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let services = WhereServices(
            store: world.store,
            compatibilityServices: world.services,
            locationSource: ScriptedLocationSource(),
            now: { now },
        )
        let gate = CompatibilityOutputTestSupport.Gate()
        await world.widgets.holdNextPublication(gate)
        let publication = Task { await services.widgets.publish() }
        await gate.waitUntilEntered()
        let withdrawal = Task { await world.services.outputs.withdraw() }
        gate.resume()
        await publication.value
        await withdrawal.value
        #expect(await world.widgets.compatibility.last?.allowsData == false)

        await services.widgets.refreshIfStale()
        #expect(await world.widgets.snapshots.count == 2)
        #expect(await world.widgets.compatibility.last?.allowsData == true)
    }

    @Test func failedEmptySnapshotPublicationRetriesOnTheNextRefresh() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let world = CompatibilityOutputTestSupport.makeWorld(
            store: SwiftDataStore(modelContainer: container),
        )
        let services = WhereServices(
            store: world.store,
            compatibilityServices: world.services,
            locationSource: ScriptedLocationSource(),
            now: { now },
        )
        await services.widgets.publish()
        #expect(await world.widgets.snapshots.count == 1)
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
        await world.widgets.failNextPublication(
            with: DataCompatibilityError.verificationFailed(description: "Injected failure"),
        )
        await services.widgets.publish()
        #expect(await world.widgets.snapshots.count == 1)
        #expect(await world.widgets.compatibility.last?.allowsData == false)

        await services.widgets.refreshIfStale()
        #expect(await world.widgets.snapshots.count == 2)
        #expect(await world.widgets.compatibility.last?.allowsData == true)
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
