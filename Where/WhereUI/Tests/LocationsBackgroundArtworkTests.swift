import RegionKit
import Testing
@testable import WhereUI

struct LocationsBackgroundArtworkTests {
    @Test func membershipIncludesBothRanksAndIgnoresRankChanges() {
        let first = RegionRanking(
            primary: [.init(region: .canada, days: 30), .init(region: .newYork, days: 20)],
            secondary: [.init(region: .other, days: 1), .init(region: .canada, days: 2)],
        )
        let reordered = RegionRanking(
            primary: [.init(region: .newYork, days: 40)],
            secondary: [.init(region: .canada, days: 30), .init(region: .other, days: 1)],
        )
        let regions = LocationsBackgroundArtwork.regions(in: first)
        #expect(Set(regions) == Set([Region.canada, .newYork, .other]))
        #expect(regions.count == 3)
        #expect(regions == LocationsBackgroundArtwork.regions(in: reordered))
        #expect(LocationsBackgroundArtwork.regions(in: .init(primary: [], secondary: [])).isEmpty)
    }

    @Test func changedMembershipHidesPreviousArtwork() async throws {
        let artwork = try #require(await LocationsBackgroundArtwork.load(
            regions: [.canada, .other],
            cache: RegionOutlinePathCache(),
        ))
        #expect(artwork.items(for: [.canada, .other]).count == 2)
        #expect(artwork.items[0].path.isEmpty == false)
        #expect(artwork.items[1].path.isEmpty)
        #expect(artwork.items(for: [.newYork]).isEmpty)
        #expect(artwork.items(for: []).isEmpty)
    }

    @MainActor
    @Test func cancelledLoadCannotPublishArtwork() async {
        let task = Task { @MainActor in
            await LocationsBackgroundArtwork.load(
                regions: [.canada],
                cache: RegionOutlinePathCache(),
            )
        }
        task.cancel()
        #expect(await task.value == nil)
    }
}
