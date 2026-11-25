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

    @Test func trackingAndDisplayFollowTheirPublisherOnLandAndWater() async throws {
        let britishColumbia = try #require(Region(rawValue: "ca-BC"))
        let offered: [Region] = [.newYork, britishColumbia, .ontario]
        let display = try await RegionGeometryCatalog.displayGeometry(for: offered)
        let tracking = RegionAttributor(for: offered)
        let controls: [(Double, Double, Region, Region?)] = [
            (40.946, -73.067, .newYork, .newYork), // Port Jefferson
            (40.998, -73.066, .newYork, nil), // Long Island Sound
            (49.28, -123.65, britishColumbia, nil), // Strait of Georgia
            (49.2827, -123.1207, britishColumbia, britishColumbia), // Vancouver
            (44.47, -79.35, .ontario, .ontario), // Lake Simcoe
            (43.60, -79.40, .other, nil), // Lake Ontario
        ]
        for (lat, lon, counted, drawn) in controls {
            let position = Coordinate(latitude: lat, longitude: lon)
            #expect(tracking.region(at: position) == counted)
            #expect(display.region(containing: position) == drawn)
        }
        let offshore = Coordinate(latitude: 40.998, longitude: -73.066)
        let match = try #require(tracking.matchWithBoundaryDistance(at: offshore))
        #expect(match.region == .newYork && match.boundaryDistance > 100)
        #expect(tracking.distanceToBoundary(of: .newYork, from: offshore) == match.boundaryDistance)
        #expect(tracking.distance(to: .newYork, from: offshore) == 0)
    }

    @Test func restoredTexasLouisianaBendCreditsTexas() throws {
        let texas = try #require(Region(rawValue: "us-TX"))
        let louisiana = try #require(Region(rawValue: "us-LA"))
        let tracker = RegionAttributor(for: [louisiana, texas])
        #expect(tracker.region(at: .init(latitude: 31.097843, longitude: -93.558908)) == texas)
    }

    @Test func restoredOntarioNunavutBendStaysWithinTrackingTolerance() throws {
        let nunavut = try #require(Region(rawValue: "ca-NU"))
        let neighbors: [Region] = [.ontario, nunavut]
        let tracker = RegionAttributor(for: neighbors)
        // Before vertex restoration, the simplified edge missed this StatCan vertex by 167 m.
        let vertex = Coordinate(latitude: 54.9925516, longitude: -82.2667869)
        for region in neighbors {
            let distance = try #require(tracker.distanceToBoundary(of: region, from: vertex))
            #expect(distance <= 25)
        }
    }

    @Test func countriesHaveNoGeometryFilesAndUSTerritoriesStayUntracked() throws {
        let catalog = RegionCatalog.shared
        let us = try #require(catalog.node(id: .init(rawValue: "united-states")))
        #expect(catalog.children(of: us).count == 52)
        #expect(us.region == nil)
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
        #expect(us.geometry == nil && canada.geometry == nil)
        for purpose in RegionGeometryPurpose.allCases {
            #expect(RegionCatalog.geometryURL(for: us, purpose: purpose) == nil)
            #expect(RegionCatalog.geometryURL(for: canada, purpose: purpose) == nil)
        }
        #expect(catalog.nodes.compactMap(\.geometry).count == 66)
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
