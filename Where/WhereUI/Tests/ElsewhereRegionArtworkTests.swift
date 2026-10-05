import RegionKit
import Testing
@testable import WhereUI

struct ElsewhereRegionArtworkTests {
    @Test func keepsOrderedRegionsAndGeometrylessOtherTogether() async throws {
        let regions: [Region] = [.canada, .other, .newYork]
        let artwork = try #require(await ElsewhereRegionArtwork.load(
            regions: regions,
            cache: RegionOutlinePathCache(),
        ))
        #expect(artwork.regions == regions)
        #expect(artwork.items.map(\.region) == regions)
        #expect(!artwork.items[0].watermark.isEmpty)
        #expect(!artwork.items[0].microprint.isEmpty)
        #expect(artwork.items[1].watermark.isEmpty)
        #expect(artwork.items[1].microprint.isEmpty)
        #expect(!artwork.items[2].watermark.isEmpty)
    }

    @Test func changedMembershipOrOrderHidesPreviousArtwork() async throws {
        let artwork = try #require(await ElsewhereRegionArtwork.load(
            regions: [.canada, .newYork],
            cache: RegionOutlinePathCache(),
        ))
        #expect(artwork.items(for: [.canada, .newYork]).count == 2)
        #expect(artwork.items(for: [.newYork, .canada]).isEmpty)
        #expect(artwork.items(for: [.europeanUnion]).isEmpty)
        #expect(artwork.items(for: []).isEmpty)
    }

    @MainActor
    @Test func cancelledLoadCannotPublishArtwork() async {
        let task = Task { @MainActor in
            await ElsewhereRegionArtwork.load(regions: [.canada], cache: RegionOutlinePathCache())
        }
        task.cancel()
        #expect(await task.value == nil)
    }
}
