import Foundation
@testable import RegionKit
import Testing

struct RegionGeometrySimplifierTests {
    @Test func toleranceReducesDenseRingsWhilePreservingIdentity() throws {
        let denseRing = (0 ..< 360).map { degrees in
            let angle = Double(degrees) * .pi / 180
            return Coordinate(latitude: sin(angle), longitude: cos(angle))
        }
        let outline = RegionOutline(
            id: RegionOutline.ID(title: "Circle", index: 0),
            title: "Circle",
            region: .california,
            coordinates: denseRing,
        )

        let medium = try #require(RegionGeometrySimplifier.simplify(
            [outline],
            tolerance: 1 / 600,
        ).first)
        let small = try #require(RegionGeometrySimplifier.simplify(
            [outline],
            tolerance: 1 / 60,
        ).first)

        #expect(outline.coordinates.count > medium.coordinates.count)
        #expect(medium.coordinates.count > small.coordinates.count)
        #expect(small.coordinates.count >= 3)
        #expect(outline.id == medium.id && medium.id == small.id)
        #expect(outline.title == medium.title && medium.title == small.title)
        #expect(outline.region == medium.region && medium.region == small.region)
        #expect(Set(medium.coordinates).isSubset(of: Set(outline.coordinates)))
        #expect(Set(small.coordinates).isSubset(of: Set(outline.coordinates)))
    }

    @Test func simplificationPreservesEveryPolygon() throws {
        let outlines = (0 ..< 3).map { index in
            RegionOutline(
                id: RegionOutline.ID(title: "Island", index: index),
                title: "Island",
                region: Region(rawValue: "us-AK"),
                coordinates: [
                    Coordinate(latitude: Double(index), longitude: 0),
                    Coordinate(latitude: Double(index) + 0.000_01, longitude: 0.000_01),
                    Coordinate(latitude: Double(index), longitude: 0.000_02),
                    Coordinate(latitude: Double(index), longitude: 0),
                ],
            )
        }

        let simplified = try RegionGeometrySimplifier.simplify(outlines, tolerance: 1 / 60)

        #expect(outlines.map(\.id) == simplified.map(\.id))
        #expect(simplified.allSatisfy { $0.coordinates.count >= 3 })
    }

    @Test func nonPositiveToleranceLeavesGeometryUnchanged() async throws {
        let outlines = await RegionGeometryCatalog.outlines(for: .california)
        #expect(try RegionGeometrySimplifier.simplify(outlines, tolerance: 0) == outlines)
    }
}
