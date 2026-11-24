import Foundation
import RegionKit
import Testing

struct RegionCatalogTimingTests {
    @Test func bundledCatalogWorkload() async throws {
        let clock = ContinuousClock()
        let sample = Coordinate(latitude: 43.65, longitude: -79.38)
        let ids = RegionCatalog.shared.all
        let start = clock.now
        let tracked = RegionAttributor(for: [.california, .newYork, .canada, .europeanUnion])
        let trackedTime = start.duration(to: clock.now)
        let allStart = clock.now
        let all = RegionAttributor(for: ids)
        let allTime = allStart.duration(to: clock.now)
        let mapStart = clock.now
        let outlines = try await RegionGeometryCatalog.outlines(for: .source, attributor: all)
        let mapTime = mapStart.duration(to: clock.now)
        let country = try #require(RegionCatalog.shared.node(id: .init(rawValue: "united-states")))
        let countryStart = clock.now
        let countryOutlines = await RegionGeometryCatalog.outlines(for: country)
        let countryTime = countryStart.duration(to: clock.now)
        #expect(!countryOutlines.isEmpty)
        let lookupStart = clock.now
        let result = all.region(at: sample)
        let lookupTime = lookupStart.duration(to: clock.now)
        #expect(tracked.region(at: sample) == .canada)
        #expect(result != .other)
        #expect(!outlines.isEmpty)
        print(
            "RegionKit timing for \(ids.count) regions: default \(trackedTime), all \(allTime), map \(mapTime), US outline \(countryTime), Toronto lookup \(lookupTime)",
        )
    }
}
