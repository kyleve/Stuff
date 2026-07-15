import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// The live attributor rebuilds when the store's tracked regions change, so a
/// synced edit (local or a remote CloudKit import, both arriving on
/// `store.changes()`) takes effect without a relaunch.
struct RegionAttributionTests {
    private let sanFrancisco = Coordinate(latitude: 37.7749, longitude: -122.4194)
    private let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298)

    @Test func rebuildsWhenTrackedRegionsChange() async throws {
        let store = try SwiftDataStore.inMemory()
        let illinois = try #require(Region(rawValue: "us-IL"))
        let attribution = RegionAttribution(
            store: store,
            initial: RegionAttributor(for: [.california]),
            trackedIDs: [Region.california.rawValue],
        )

        #expect(attribution.region(at: sanFrancisco) == .california)
        #expect(attribution.region(at: chicago) == .other)

        // Switch the tracked set to Illinois. The commit pings `changes()` (the
        // observer reconciles); reconcile again for a deterministic assertion.
        try await store.perform {
            try await store.setTrackedRegion(true, id: illinois.rawValue)
        }
        await attribution.reconcile()

        #expect(attribution.region(at: chicago) == illinois)
        // California is no longer tracked, so SF falls through to `.other`.
        #expect(attribution.region(at: sanFrancisco) == .other)
        #expect(Set(attribution.loadedRegions) == [illinois])
    }

    @Test func reconcileIsANoOpWhenTheSetIsUnchanged() async throws {
        let store = try SwiftDataStore.inMemory()
        let attribution = RegionAttribution(
            store: store,
            initial: RegionAttributor(for: Array(SwiftDataStore.defaultTrackedRegions)),
            trackedIDs: Set(SwiftDataStore.defaultTrackedRegions.map(\.rawValue)),
        )
        // No rows persisted → `trackedRegions()` still returns the default four,
        // matching the initial set, so nothing rebuilds and attribution holds.
        await attribution.reconcile()
        #expect(attribution.region(at: sanFrancisco) == .california)
    }
}
