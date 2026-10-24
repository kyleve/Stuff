import Foundation
import Testing
@_spi(Testing) import ThrowCore
@testable import ThrowUI

struct StaticLineProjectionCacheTests {
    @Test func evictsTheLeastRecentlyUsedProjectionAtCapacity() throws {
        var cache = StaticLineProjectionCache<GeographyLayerKind>()
        let keys = try (0 ... 8).map { try key(longitude: -122 + Double($0)) }
        for index in 0 ..< 8 {
            cache.insert(frame(id: UInt64(index + 1)), for: keys[index])
        }

        #expect(cache.frame(for: keys[0])?.lines.id == ProjectionLineRevisionID
            .testing(rawValue: 1))
        cache.insert(frame(id: 9), for: keys[8])

        #expect(cache.frame(for: keys[1]) == nil)
        #expect(cache.frame(for: keys[0])?.lines.id == ProjectionLineRevisionID
            .testing(rawValue: 1))
        #expect(cache.frame(for: keys[8])?.lines.id == ProjectionLineRevisionID
            .testing(rawValue: 9))
    }

    @Test func replacingAProjectionDoesNotEvictAnotherKey() throws {
        var cache = StaticLineProjectionCache<GeographyLayerKind>()
        let keys = try (0 ..< 8).map { try key(longitude: -122 + Double($0)) }
        let replacement = frame(id: 99)
        for index in keys.indices {
            cache.insert(frame(id: UInt64(index + 1)), for: keys[index])
        }

        cache.insert(replacement, for: keys[0])

        #expect(cache.frame(for: keys[0])?.lines.id == replacement.lines.id)
        for key in keys.dropFirst() {
            #expect(cache.frame(for: key) != nil)
        }
    }

    private func key(longitude: Double) throws
        -> StaticLineProjectionCache<GeographyLayerKind>.Key
    {
        try StaticLineProjectionCache<GeographyLayerKind>.Key(
            revision: Date(timeIntervalSince1970: 1),
            mapCenter: GeoCoordinate(latitude: 37, longitude: longitude),
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )
    }

    private func frame(id: UInt64) -> ProjectedLayerFrame<GeographyLayerKind> {
        .testing(lines: ProjectedLineCollection.testing(
            id: ProjectionLineRevisionID.testing(rawValue: id),
            segments: [],
        ))
    }
}
