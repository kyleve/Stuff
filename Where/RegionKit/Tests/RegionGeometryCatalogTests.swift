import Foundation
@testable import RegionKit
import Synchronization
import Testing

struct RegionGeometryCatalogTests {
    @Test func artworkReadsOnlyTheRequestedDisplayFileOnce() async throws {
        let catalog = RegionCatalog.shared
        let reads = Mutex<[String]>([])
        let cache = RegionGeometryCatalog.RegionCache(catalog: catalog) { node, purpose in
            reads.withLock { $0.append(node.geometry?[purpose].file ?? node.id.rawValue) }
            return RegionCatalog.geometryURL(for: node, purpose: purpose)
        }
        for id in ["canada", "united-states", "other"] {
            #expect(try await cache.outlines(for: Region(unchecked: id)).isEmpty)
        }
        #expect(reads.withLock { $0.isEmpty })
        let outlines = try await cache.outlines(for: .newYork)
        #expect(!outlines.isEmpty && outlines.allSatisfy { $0.region == .newYork })
        #expect(try await cache.outlines(for: .newYork) == outlines)
        #expect(reads.withLock { $0 } == ["us/us-NY.display.twkb"])
    }

    @Test func missingDisplayFileCannotAffectTracking() throws {
        let catalog = RegionCatalog.shared
        func onlyTracking(_ node: RegionCatalog.Node, _ purpose: RegionGeometryPurpose) -> URL? {
            purpose == .tracking ? RegionCatalog.geometryURL(for: node, purpose: purpose) : nil
        }
        #expect(throws: RegionGeometryError.self) {
            try RegionGeometryCatalog.displayGeometry(
                for: [.newYork],
                catalog: catalog,
                resourceURL: onlyTracking,
            )
        }
        let tracker = RegionAttributor(for: [.newYork], catalog: catalog, geometryURL: onlyTracking)
        #expect(tracker.region(at: .init(latitude: 40.998, longitude: -73.066)) == .newYork)
    }

    @Test func batchSkipsOtherAndDuplicatesWithStableUniqueIDs() async throws {
        let batch = try await RegionGeometryCatalog.displayGeometry(for: [
            .other,
            .newYork,
            .california,
            .other,
            .newYork,
        ])
        let unique = try await RegionGeometryCatalog.displayGeometry(for: [.newYork, .california])
        #expect(!batch.outlines.isEmpty && batch.outlines == unique.outlines)
        #expect(Set(batch.outlines.map(\.id)).count == batch.outlines.count)
        #expect(batch.outlines.first?.region == .newYork && batch.outlines.last?
            .region == .california)
        let empty = try await RegionGeometryCatalog.displayGeometry(for: [])
        #expect(empty.outlines.isEmpty && empty.region(containing: .init(
            latitude: 0,
            longitude: 0,
        )) == nil)
        #expect(await RegionGeometryCatalog.displayOutlines(for: .other).isEmpty)
    }

    @Test func displayLookupRespectsHolesAndOfferedPriority() {
        func ring(_ radius: Double) -> [Coordinate] {
            [(-radius, -radius), (-radius, radius), (radius, radius), (radius, -radius)].map {
                Coordinate(latitude: $0.0, longitude: $0.1)
            }
        }
        let shell = GeoPolygon(vertices: ring(5), holes: [ring(1)])
        let solid = GeoPolygon(vertices: ring(3))
        let outer = RegionPolygons(region: .ontario, polygons: [shell])
        let inner = RegionPolygons(region: .newYork, polygons: [solid])
        let map = RegionDisplayGeometry(entries: [outer, inner])
        #expect(map.outlines.first?.holes == shell.holes)
        #expect(map.region(containing: .init(latitude: 0, longitude: 0)) == .newYork)
        let overlap = Coordinate(latitude: 2, longitude: 2)
        #expect(map.region(containing: overlap) == .ontario)
        #expect(RegionDisplayGeometry(entries: [inner, outer])
            .region(containing: overlap) == .newYork)
    }

    @Test func allCatalogRegionsDrawInBothModesAndAlaskaSpansTheAntimeridian() async throws {
        let catalog = RegionCatalog.shared
        let display = try await RegionGeometryCatalog.displayGeometry(for: catalog.all)
        let tracking = RegionGeometryCatalog.trackingOutlines(for: .all)
        for outlines in [display.outlines, tracking] {
            #expect(Set(outlines.compactMap(\.region)) == Set(catalog.all))
            #expect(outlines.allSatisfy { $0.region != nil && $0.coordinates.count >= 3 })
            #expect(Set(outlines.map(\.id)).count == outlines.count)
        }
        let alaska = try #require(Region(rawValue: "us-AK"))
        for fix in [
            Coordinate(latitude: 52.84, longitude: 173.19),
            Coordinate(latitude: 51.88, longitude: -176.64),
        ] {
            #expect(display.region(containing: fix) == alaska)
        }
    }

    @Test func outlineHashesByIdNotCoordinates() {
        let id = RegionOutline.ID(title: "California", index: 0)
        let a = RegionOutline(
            id: id,
            title: "California",
            region: .california,
            coordinates: [
                Coordinate(latitude: 0, longitude: 0),
                Coordinate(latitude: 1, longitude: 1),
                Coordinate(latitude: 2, longitude: 2),
            ],
        )
        let b = RegionOutline(
            id: id,
            title: "California",
            region: .california,
            coordinates: [
                Coordinate(latitude: 9, longitude: 9),
                Coordinate(latitude: 8, longitude: 8),
                Coordinate(latitude: 7, longitude: 7),
            ],
        )
        // Same identity → same hash, no matter how big or different the
        // coordinate rings are...
        #expect(a.hashValue == b.hashValue)
        // ...while value equality still distinguishes the differing rings.
        #expect(a != b)
    }

    // MARK: - Bounding box

    @Test func boundingBox_enclosesEveryOutlineCoordinate() throws {
        let tracker = RegionAttributor(for: [.newYork])
        let outlines = RegionGeometryCatalog.trackingOutlines(for: tracker)
        #expect(outlines.allSatisfy { $0.region == .newYork })
        let box = try #require(BoundingBox.enclosing(outlines))
        #expect(outlines.allSatisfy { $0.coordinates.allSatisfy(box.contains) })
    }

    @Test func boundingBox_ofEmptyOutlinesIsNil() {
        #expect(BoundingBox.enclosing([] as [RegionOutline]) == nil)
    }

    // MARK: - Errors

    @Test func missingResourceErrorNamesTheFile() {
        let error = RegionGeometryError.missingResource("us-states.geojson")
        // `errorDescription` (LocalizedError) is what the viewer renders;
        // it must name the file, not fall back to the generic message.
        #expect(error.errorDescription?.contains("us-states.geojson") == true)
        #expect(error.localizedDescription.contains("us-states.geojson"))
    }

    @Test func emptyResourceErrorNamesTheFile() {
        let error = RegionGeometryError.emptyResource("us-CA.twkb")
        #expect(error.errorDescription?.contains("us-CA.twkb") == true)
        #expect(error.localizedDescription.contains("us-CA.twkb"))
    }
}
