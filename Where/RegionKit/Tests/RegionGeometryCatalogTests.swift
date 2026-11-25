@testable import RegionKit
import Synchronization
import Testing

struct RegionGeometryCatalogTests {
    /// A representative tracked subset, so `.attribution` outlines reflect a
    /// specific attributor rather than a global.
    let tracked = RegionAttributor(for: [.california, .newYork, .ontario, .europeanUnion])

    // MARK: - Attribution

    @Test func region_coversOnlyTheRequestedRegion() async {
        let outlines = await RegionGeometryCatalog.outlines(for: .california)
        #expect(!outlines.isEmpty)
        #expect(outlines.allSatisfy { $0.region == .california })
        #expect(outlines.allSatisfy { $0.title == Region.california.localizedName })
    }

    @Test func otherRegion_hasNoDrawableOutlines() async {
        #expect(await RegionGeometryCatalog.outlines(for: .other).isEmpty)
    }

    @Test func subdivisionArtworkLoadsOnceAndCountryNodesHaveNoArtwork() async throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let reads = Mutex<[RegionCatalog.Node.ID]>([])
        let fixtureURL = try #require(RegionCatalog.shared.geometryURL(for: .california))
        let cache = RegionGeometryCatalog.RegionCache(catalog: catalog) { node in
            reads.withLock { $0.append(node.id) }
            return fixtureURL
        }
        for id in ["canada", "united-states"] {
            #expect(try await cache.outlines(for: Region(unchecked: id)).isEmpty)
        }
        #expect(reads.withLock { $0.isEmpty })
        let outlines = try await cache.outlines(for: .ontario)
        #expect(!outlines.isEmpty && outlines.allSatisfy { $0.region == .ontario })
        #expect(try await cache.outlines(for: .ontario) == outlines)
        #expect(reads.withLock { $0.map(\.rawValue) } == ["ca-ON"])
    }

    @Test func missingSubdivisionArtworkSurfacesItsResourceError() async throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let cache = RegionGeometryCatalog.RegionCache(catalog: catalog) { _ in nil }
        await #expect(throws: RegionGeometryError.self) { try await cache.outlines(for: .ontario) }
    }

    @Test func attribution_coversExactlyTheAttributorsRegions() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(
            for: .attribution,
            attributor: tracked,
        )
        let regions = Set(outlines.compactMap(\.region))
        #expect(regions == [.california, .newYork, .ontario, .europeanUnion])
    }

    @Test func attribution_everyOutlineIsTaggedWithARealRegion() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(
            for: .attribution,
            attributor: tracked,
        )
        #expect(!outlines.isEmpty)
        #expect(outlines.allSatisfy { $0.region != nil && $0.region != .other })
    }

    // MARK: - Source

    @Test func source_decodesAll52USStateFeatures() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(for: .source, attributor: .all)
        let us = try #require(RegionCatalog.shared.node(id: .init(rawValue: "united-states")))
        let children = Set(RegionCatalog.shared.children(of: us).compactMap(\.region))
        #expect(children.count == 52)
        #expect(children.isSubset(of: Set(outlines.compactMap(\.region))))
        #expect(outlines.allSatisfy { $0.region != nil })
    }

    @Test func sourceAndAllTrackedGeometryDrawEachPhysicalRegionOnce() async throws {
        let catalog = RegionCatalog.shared
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
        let childRegions = Set(catalog.children(of: canada).compactMap(\.region))
        let source = try await RegionGeometryCatalog.outlines(for: .source, attributor: .all)
        let attributed = try await RegionGeometryCatalog.outlines(
            for: .attribution,
            attributor: .all,
        )
        let owners = Set(source.compactMap(\.region))
        #expect(childRegions.isSubset(of: owners))
        #expect(owners == Set(catalog.all))
        #expect(owners == Set(attributed.compactMap(\.region)))
        #expect(source.count == attributed.count)
    }

    @Test func source_tagsEveryStateWithItsRegion() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(for: .source, attributor: .all)
        let california = try #require(outlines.first { $0.title == "California" })
        #expect(california.region == .california)
        let newYork = try #require(outlines.first { $0.title == "New York" })
        #expect(newYork.region == .newYork)
        // Every US state is now a first-class catalog region — no untagged
        // source features remain.
        let texas = try #require(outlines.first { $0.title == "Texas" })
        #expect(texas.region == Region(rawValue: "us-TX"))
        #expect(outlines.allSatisfy { $0.region != nil })
    }

    // MARK: - Outline shape

    @Test func outlineIDsAreUniqueWithinAResult() async throws {
        for kind in RegionGeometryKind.allCases {
            let outlines = try await RegionGeometryCatalog.outlines(for: kind, attributor: .all)
            #expect(Set(outlines.map(\.id)).count == outlines.count)
        }
    }

    @Test func everyOutlineRingHasAtLeastThreeVertices() async throws {
        for kind in RegionGeometryKind.allCases {
            let outlines = try await RegionGeometryCatalog.outlines(for: kind, attributor: .all)
            #expect(outlines.allSatisfy { $0.coordinates.count >= 3 })
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

    @Test func boundingBox_enclosesEveryOutlineCoordinate() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(
            for: .attribution,
            attributor: tracked,
        )
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
