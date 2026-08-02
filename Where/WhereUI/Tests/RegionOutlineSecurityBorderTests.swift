import CoreGraphics
import Testing
@testable import WhereUI

struct RegionOutlineSecurityBorderTests {
    @Test func placementsFollowTheInsetRoundedPerimeter() throws {
        let placements = RegionOutlineSecurityBorder.placements(
            in: CGSize(width: 320, height: 180),
            cornerRadius: 28,
            inset: 9,
            spacing: 11,
        )

        #expect(placements.count > 80)
        let first = try #require(placements.first)
        #expect(first.center == CGPoint(x: 28, y: 9))
        #expect(first.rotation == 0)
        #expect(placements.allSatisfy { placement in
            placement.center.x >= 9 && placement.center.x <= 311
                && placement.center.y >= 9 && placement.center.y <= 171
        })
    }

    @Test func invalidGeometryHasNoPlacements() {
        #expect(RegionOutlineSecurityBorder.placements(
            in: .zero,
            cornerRadius: 28,
            inset: 9,
            spacing: 13,
        ).isEmpty)
        #expect(RegionOutlineSecurityBorder.placements(
            in: CGSize(width: 320, height: 180),
            cornerRadius: 28,
            inset: 9,
            spacing: 0,
        ).isEmpty)
    }

    @Test func squareCornersHaveFinitePlacements() {
        let placements = RegionOutlineSecurityBorder.placements(
            in: CGSize(width: 320, height: 180),
            cornerRadius: 0,
            inset: 9,
            spacing: 11,
        )

        #expect(!placements.isEmpty)
        #expect(placements.allSatisfy { placement in
            placement.center.x.isFinite
                && placement.center.y.isFinite
                && placement.rotation.isFinite
        })
    }
}
