import RegionKit
import Testing
@testable import WhereIntents

/// `RegionEntity` is a lossless, `rawValue`-keyed mirror of `Region`, and its
/// query resolves the fixed five-case set.
struct RegionEntityTests {
    @Test func roundTripsEveryRegion() {
        for region in Region.allCases {
            let entity = RegionEntity(region)
            #expect(entity.id == region.rawValue)
            #expect(entity.region == region)
        }
    }

    @Test func allCoversEveryRegionInDeclarationOrder() {
        #expect(RegionEntity.all.map(\.region) == Region.allCases)
    }

    @Test func queryResolvesKnownIdsAndDropsUnknown() async throws {
        let query = RegionEntityQuery()
        let resolved = try await query.entities(for: ["us-CA", "bogus", "canada"])
        #expect(resolved.map(\.region) == [.california, .canada])
    }

    @Test func suggestedEntitiesAreEveryRegion() async throws {
        let suggested = try await RegionEntityQuery().suggestedEntities()
        #expect(suggested.map(\.region) == Region.allCases)
    }
}
