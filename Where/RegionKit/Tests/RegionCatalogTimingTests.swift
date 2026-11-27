import Foundation
import RegionKit
import Testing

struct RegionCatalogTimingTests {
    @Test func bundledCatalogWorkload() async throws {
        let clock = ContinuousClock()
        let sample = Coordinate(latitude: 43.65, longitude: -79.38)
        let ids = RegionCatalog.shared.all
        let start = clock.now
        let tracked = RegionAttributor(for: [.california, .newYork, .europeanUnion])
        let trackedTime = start.duration(to: clock.now)
        let allStart = clock.now
        let all = RegionAttributor(for: ids)
        let allTime = allStart.duration(to: clock.now)
        let cardStart = clock.now
        let card = await RegionGeometryCatalog.displayOutlines(for: .newYork)
        let cardTime = cardStart.duration(to: clock.now)
        let mapStart = clock.now
        let map = try await RegionGeometryCatalog.displayGeometry(for: ids)
        let mapTime = mapStart.duration(to: clock.now)
        let lookupStart = clock.now
        let result = all.region(at: sample)
        let lookupTime = lookupStart.duration(to: clock.now)
        #expect(tracked.region(at: sample) == .other)
        #expect(result == .ontario)
        #expect(!card.isEmpty && !map.outlines.isEmpty)
        print(
            "RegionKit timing for \(ids.count) regions: default \(trackedTime), all \(allTime), card \(cardTime), map \(mapTime), Toronto lookup \(lookupTime)",
        )
    }
}
