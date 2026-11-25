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
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
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

    @Test func fixesOnEitherSideOfTheOntarioQuebecBorderMatchTheirTrackedProvince() throws {
        let quebec = try #require(Region(rawValue: "ca-QC"))
        let west = Coordinate(latitude: 48.5, longitude: -79.5195)
        let east = Coordinate(latitude: 48.5, longitude: -79.5155)
        let both = RegionAttributor(for: [.ontario, quebec])
        let ontarioMatch = try #require(both.matchWithBoundaryDistance(at: west))
        let quebecMatch = try #require(both.matchWithBoundaryDistance(at: east))
        #expect(ontarioMatch.region == .ontario && ontarioMatch.boundaryDistance < 500)
        #expect(quebecMatch.region == quebec && quebecMatch.boundaryDistance < 500)
        #expect(RegionAttributor(for: [.ontario]).region(at: east) == .other)
    }

    @Test func publisherOverlapAtTheAlaskaYukonBorderUsesCallerPriority() throws {
        let alaska = try #require(Region(rawValue: "us-AK"))
        let yukon = try #require(Region(rawValue: "ca-YT"))
        let alaskaFirst = RegionAttributor(for: [alaska, yukon])
        let yukonFirst = RegionAttributor(for: [yukon, alaska])
        let overlap = Coordinate(latitude: 64, longitude: -141.002)
        #expect(alaskaFirst.region(at: overlap) == alaska)
        #expect(yukonFirst.region(at: overlap) == yukon)
        #expect(alaskaFirst.distance(to: yukon, from: overlap) == 0)
        #expect(yukonFirst.distance(to: alaska, from: overlap) == 0)

        // Just west of both publishers' edges, leaving Alaska and entering Yukon
        // change the winner at different distances depending on caller priority.
        let alaskaOnly = Coordinate(latitude: 64, longitude: -141.004)
        let toAlaskaEdge = try #require(alaskaFirst.distanceToBoundary(
            of: alaska,
            from: alaskaOnly,
        ))
        let toYukonEdge = try #require(alaskaFirst.distanceToBoundary(of: yukon, from: alaskaOnly))
        #expect(toYukonEdge < toAlaskaEdge)
        let first = try #require(alaskaFirst.matchWithBoundaryDistance(at: alaskaOnly))
        let second = try #require(yukonFirst.matchWithBoundaryDistance(at: alaskaOnly))
        #expect(first.region == alaska && first.boundaryDistance == toAlaskaEdge)
        #expect(second.region == alaska && second.boundaryDistance == toYukonEdge)
    }

    @Test func countriesHaveNoGeometryFilesAndUSTerritoriesStayUntracked() throws {
        let catalog = RegionCatalog.shared
        let us = try #require(catalog.node(id: .init(rawValue: "united-states")))
        #expect(catalog.children(of: us).count == 52)
        #expect(us.region == nil)
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
        #expect(us.geometryFile == nil && canada.geometryFile == nil)
        #expect(RegionCatalog.geometryURL(for: us) == nil && RegionCatalog
            .geometryURL(for: canada) == nil)
        #expect(catalog.nodes.compactMap(\.geometryFile).count == 66)
        let countries = [us, canada].map { Region(unchecked: $0.id.rawValue) }
        #expect(canada.region == nil)
        #expect(RegionAttributor(for: countries).loadedRegions.isEmpty)
        for (code, latitude, longitude) in [
            ("AS", -14.279, -170.701),
            ("GU", 13.4757, 144.7504),
            ("MP", 15.2, 145.75),
            ("VI", 18.3419, -64.9307),
        ] {
            let fix = Coordinate(latitude: latitude, longitude: longitude)
            #expect(Region(rawValue: "us-\(code)") == nil)
            #expect(RegionAttributor.all.region(at: fix) == .other)
        }
        let border = Coordinate(latitude: 39.7, longitude: -120.001)
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
