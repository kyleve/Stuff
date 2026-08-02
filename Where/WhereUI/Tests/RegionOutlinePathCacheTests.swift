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
        let repeatedSmall = await cache.path(for: alaska, resolution: .small)

        #expect(!full.isEmpty)
        #expect(elementCount(full) > elementCount(medium))
        #expect(elementCount(medium) > elementCount(small))
        #expect(full.boundingRect == medium.boundingRect)
        #expect(medium.boundingRect == small.boundingRect)
        #expect(repeatedSmall == small)
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

    private func elementCount(_ path: Path) -> Int {
        var count = 0
        path.forEach { _ in count += 1 }
        return count
    }
}
