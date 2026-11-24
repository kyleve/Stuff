import Foundation
@testable import RegionKit
import Testing

struct NorthAmericanRegionTests {
    @Test func everyCanadianCapitalResolvesToItsSubdivision() throws {
        let capitals = [
            ("AB", 53.5461, -113.4938),
            ("BC", 48.4284, -123.3656),
            ("MB", 49.8951, -97.1385),
            ("NB", 45.9636, -66.6431),
            ("NL", 47.5615, -52.7126),
            ("NS", 44.6488, -63.5752),
            ("NT", 62.4540, -114.3718),
            ("NU", 63.7467, -68.5167),
            ("ON", 43.6532, -79.3832),
            ("PE", 46.2382, -63.1311),
            ("QC", 46.8139, -71.2080),
            ("SK", 50.4452, -104.6189),
            ("YT", 60.7212, -135.0568),
        ]
        let catalog = RegionCatalog.shared
        let canada = try #require(catalog.node(for: .canada))
        let children = catalog.children(of: canada)
        #expect(children.count == capitals.count)
        #expect(children.count(where: { $0.kind == .territory }) == 3)
        for (code, latitude, longitude) in capitals {
            let region = try #require(Region(rawValue: "ca-\(code)"))
            #expect(children.contains { $0.region == region })
            let fix = Coordinate(latitude: latitude, longitude: longitude)
            #expect(RegionAttributor.all.region(at: fix) == region)
        }
    }

    @Test func trackedOntarioControlsConfidenceOnEitherSideOfItsBoundary() throws {
        let ontario = try #require(Region(rawValue: "ca-ON"))
        let west = Coordinate(latitude: 48.5, longitude: -79.5195)
        let east = Coordinate(latitude: 48.5, longitude: -79.5155)
        let both = RegionAttributor(for: [.canada, ontario])
        let inside = try #require(both.matchWithBoundaryDistance(at: west))
        let outside = try #require(both.matchWithBoundaryDistance(at: east))
        #expect(inside.region == ontario)
        #expect(outside.region == .canada)
        #expect(inside.boundaryDistance < 500 && outside.boundaryDistance < 500)
        let canada = RegionAttributor(for: [.canada])
        #expect(try #require(canada.distanceToBoundary(of: .canada, from: west)) > 10000)
        #expect(both.distance(to: .canada, from: west) == 0)
        let vancouver = Coordinate(latitude: 49.28, longitude: -123.12)
        #expect(both.region(at: vancouver) == .canada)
        #expect(RegionAttributor(for: [ontario]).region(at: vancouver) == .other)
    }

    @Test func usCountryUnitesStatesAndUntrackedTerritories() async throws {
        let catalog = RegionCatalog.shared
        let us = try #require(catalog.node(id: .init(rawValue: "united-states")))
        #expect(catalog.children(of: us).count == 52)
        #expect(us.region == nil)
        let outlines = await RegionGeometryCatalog.outlines(for: us)
        #expect(!outlines.isEmpty && outlines.allSatisfy { $0.region == nil })
        let polygons = outlines.map { GeoPolygon(vertices: $0.coordinates, holes: $0.holes) }
        for (code, latitude, longitude) in [
            ("AS", -14.279, -170.701),
            ("GU", 13.4757, 144.7504),
            ("MP", 15.2, 145.75),
            ("VI", 18.3419, -64.9307),
        ] {
            let fix = Coordinate(latitude: latitude, longitude: longitude)
            #expect(Region(rawValue: "us-\(code)") == nil)
            #expect(polygons.contains { $0.contains(fix) })
            #expect(RegionAttributor.all.region(at: fix) == .other)
        }
        let border = Coordinate(latitude: 39.7, longitude: -120.001)
        let countryDistance = polygons.reduce(Double.infinity) { $1.distanceToBoundary(
            from: border,
            nearerThan: $0,
        ) }
        #expect(countryDistance > 10000)
        #expect(try #require(RegionAttributor.all.distanceToBoundary(
            of: .california,
            from: border,
        )) < 500)
        let alaska = try #require(Region(rawValue: "us-AK"))
        for fix in [
            Coordinate(latitude: 52.84, longitude: 173.19),
            Coordinate(latitude: 51.88, longitude: -176.64),
        ] {
            #expect(RegionAttributor.all.region(at: fix) == alaska)
        }
    }
}
