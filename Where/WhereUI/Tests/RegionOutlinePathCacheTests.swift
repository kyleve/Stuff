import RegionKit
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

struct RegionOutlinePathCacheTests {
    @Test func cachesProgressivelySimplifiedPathsWithStableFraming() async throws {
        let alaska = try #require(Region(rawValue: "us-AK"))
        let cache = RegionOutlinePathCache()
        let full = await cache.path(for: alaska, resolution: .full)
        let medium = await cache.path(for: alaska, resolution: .medium)
        let small = await cache.path(for: alaska, resolution: .small)
        let micro = await cache.path(for: alaska, resolution: .micro)
        let repeatedMicro = await cache.path(for: alaska, resolution: .micro)

        #expect(!full.isEmpty)
        #expect(elementCount(full) > elementCount(medium))
        #expect(elementCount(medium) > elementCount(small))
        #expect(elementCount(small) > elementCount(micro))
        #expect(full.boundingRect == medium.boundingRect)
        #expect(medium.boundingRect == small.boundingRect)
        #expect(small.boundingRect == micro.boundingRect)
        #expect(repeatedMicro == micro)
    }

    @Test func otherRegionHasNoPath() async {
        let cache = RegionOutlinePathCache()
        let path = await cache.path(for: .other, resolution: .full)
        #expect(path.isEmpty)
    }

    @Test func smallResolutionRetainsThinNewYorkGeography() async throws {
        let cache = RegionOutlinePathCache()
        let small = await cache.path(for: .newYork, resolution: .small)
        let outlines = await RegionGeometryCatalog.displayOutlines(for: .newYork)
        let projection = try #require(RegionArtworkProjection(outlines: outlines))
        // Sample the eastern end of Long Island and the open Atlantic south of
        // it. This guards the silhouette independently of the publisher's vertex count.
        #expect(small.contains(projection.point(for: .init(latitude: 40.97, longitude: -72.17))))
        #expect(!small.contains(projection.point(for: .init(latitude: 40.69, longitude: -72.18))))
    }

    @Test func offshoreTrackingFixProjectsOutsideTheDisplayedCardMask() async throws {
        let coast = Coordinate(latitude: 40.946, longitude: -73.067)
        let sound = Coordinate(latitude: 40.998, longitude: -73.066)
        let cache = RegionOutlinePathCache()
        let path = await cache.path(for: .newYork, resolution: .full)
        let locations = [coast, sound]
            .map { RegionDayPoint(coordinate: $0, horizontalAccuracy: 10) }
        let dots = await cache.projectedPoints(for: .newYork, points: locations)
        try #require(dots.count == 2)
        #expect(path.contains(dots[0].position))
        #expect(!path.contains(dots[1].position))
        #expect(RegionAttributor(for: [.newYork]).region(at: sound) == .newYork)
    }

    @Test func microResolutionBoundsRepeatedBorderDetail() async {
        let cache = RegionOutlinePathCache()
        let micro = await cache.path(for: .newYork, resolution: .micro)

        #expect(!micro.isEmpty)
        #expect(
            elementCount(micro) <= 60,
            "The repeated eight-point border path should stay within its rendering budget.",
        )
    }

    private func elementCount(_ path: Path) -> Int {
        var count = 0
        path.forEach { _ in count += 1 }
        return count
    }
}
