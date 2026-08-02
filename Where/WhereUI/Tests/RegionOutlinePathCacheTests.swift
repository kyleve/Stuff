import RegionKit
import SwiftUI
import Testing
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

    @Test func smallResolutionRetainsThinNewYorkGeography() async {
        let cache = RegionOutlinePathCache()
        let small = await cache.path(for: .newYork, resolution: .small)

        #expect(
            elementCount(small) >= 110,
            "The stamp path should retain Long Island instead of reducing it to a coarse wedge.",
        )
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
