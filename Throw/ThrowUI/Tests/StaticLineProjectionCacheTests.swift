import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct StaticLineProjectionCacheTests {
    @Test func evictsTheLeastRecentlyUsedProjectionAtCapacity() throws {
        var cache = StaticLineProjectionCache()
        let keys = try (0 ... 8).map { try key(longitude: -122 + Double($0)) }
        for index in 0 ..< 8 {
            cache.insert(projection(id: UInt64(index + 1)), for: keys[index])
        }

        #expect(cache.projection(for: keys[0])?.id == ProjectionLineRevisionID(rawValue: 1))
        cache.insert(projection(id: 9), for: keys[8])

        #expect(cache.projection(for: keys[1]) == nil)
        #expect(cache.projection(for: keys[0])?.id == ProjectionLineRevisionID(rawValue: 1))
        #expect(cache.projection(for: keys[8])?.id == ProjectionLineRevisionID(rawValue: 9))
    }

    @Test func replacingAProjectionDoesNotEvictAnotherKey() throws {
        var cache = StaticLineProjectionCache()
        let keys = try (0 ..< 8).map { try key(longitude: -122 + Double($0)) }
        let replacement = projection(id: 99)
        for index in keys.indices {
            cache.insert(projection(id: UInt64(index + 1)), for: keys[index])
        }

        cache.insert(replacement, for: keys[0])

        #expect(cache.projection(for: keys[0])?.id == replacement.id)
        for key in keys.dropFirst() {
            #expect(cache.projection(for: key) != nil)
        }
    }

    private func key(longitude: Double) throws -> StaticLineProjectionCache.Key {
        try StaticLineProjectionCache.Key(
            layerID: .geography,
            revision: Date(timeIntervalSince1970: 1),
            mapCenter: GeoCoordinate(latitude: 37, longitude: longitude),
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
        )
    }

    private func projection(id: UInt64) -> ProjectedLineCollection {
        ProjectedLineCollection(
            id: ProjectionLineRevisionID(rawValue: id),
            segments: [],
        )
    }
}
