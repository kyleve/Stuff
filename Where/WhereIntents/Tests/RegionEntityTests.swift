import RegionKit
import Testing
import WhereCore
@testable import WhereIntents

/// `RegionEntity` is a lossless, `rawValue`-keyed mirror of `Region`. Its query
/// resolves any *available* region by id, while its suggestions / Spotlight
/// index surface the user's *tracked* set.
struct RegionEntityTests {
    @Test func roundTripsEveryRegion() {
        for region in Region.allCases {
            let entity = RegionEntity(region)
            #expect(entity.id == region.rawValue)
            #expect(entity.region == region)
        }
    }

    @Test func queryResolvesAnyCatalogRegionAndDropsUnknown() async throws {
        let query = RegionEntityQuery()
        let texas = try #require(Region(rawValue: "us-TX"))
        // Resolves any available region by id — including untracked ones like
        // Texas ("days in Texas" still answers) — and drops unknown ids.
        let resolved = try await query.entities(for: ["us-CA", "us-TX", "bogus", "canada"])
        #expect(resolved.map(\.region) == [.california, texas, .canada])
    }

    @Test func trackedEntitiesFollowTheStoresTrackedSet() async throws {
        let store = try SwiftDataStore.inMemory()
        let texas = try #require(Region(rawValue: "us-TX"))
        try await store.perform {
            try await store.setTrackedRegion(true, region: .california)
            try await store.setTrackedRegion(true, region: texas)
        }
        let entities = try await RegionEntity
            .tracked(from: IntentTestSupport.services(store: store))
        // Canonical order: California (us-CA) precedes Texas (us-TX).
        #expect(entities.map(\.region) == [.california, texas])
    }

    @Test func trackedEntitiesDefaultToTheFourWhenUnset() async throws {
        let store = try SwiftDataStore.inMemory()
        let entities = try await RegionEntity
            .tracked(from: IntentTestSupport.services(store: store))
        #expect(Set(entities.map(\.region)) == SwiftDataStore.defaultTrackedRegions)
    }
}
