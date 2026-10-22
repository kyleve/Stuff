import RegionKit
import Testing
@testable import WhereUI

@MainActor
struct LocationForecastArtworkTests {
    @Test func summaryKeepsPrimaryOrderAndBothCachedResolutions() async throws {
        let cache = RegionOutlinePathCache()
        let regions: [Region] = [.newYork, .california]
        let artwork = try #require(await LocationForecastArtwork.loadSummary(
            regions: regions,
            cache: cache,
        ))
        #expect(artwork.map(\.region) == regions)
        for item in artwork {
            let watermark = await cache.path(for: item.region, resolution: .medium)
            let microprint = await cache.path(for: item.region, resolution: .micro)
            #expect(item.watermark == watermark)
            #expect(item.microprint == microprint)
        }
        let border = await LocationForecastArtwork.load(regions: regions, cache: cache)
        #expect(border == artwork.map(\.microprint))
    }

    @Test func cancelledSummaryDoesNotPublishArtwork() async {
        let cache = RegionOutlinePathCache()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await LocationForecastArtwork.loadSummary(regions: [.california], cache: cache)
        }
        #expect(await task.value == nil)
    }
}
