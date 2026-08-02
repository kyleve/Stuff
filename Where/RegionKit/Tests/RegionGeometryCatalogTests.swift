@testable import RegionKit
import Testing

struct RegionGeometryCatalogTests {
    /// A representative tracked subset, so `.attribution` outlines reflect a
    /// specific attributor rather than a global.
    let trackedFour = RegionAttributor(for: [.california, .newYork, .canada, .europeanUnion])

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

    @Test func attribution_coversExactlyTheAttributorsRegions() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(
            for: .attribution,
            attributor: trackedFour,
        )
        let regions = Set(outlines.compactMap(\.region))
        #expect(regions == [.california, .newYork, .canada, .europeanUnion])
    }

    @Test func attribution_everyOutlineIsTaggedWithARealRegion() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(
            for: .attribution,
            attributor: trackedFour,
        )
        #expect(!outlines.isEmpty)
        #expect(outlines.allSatisfy { $0.region != nil && $0.region != .other })
    }

    // MARK: - Source

    @Test func source_decodesAll52USStateFeatures() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(for: .source, attributor: .all)
        // Distinct titles minus the two bundled-file regions are the US
        // Census features (50 states + DC + Puerto Rico = 52).
        let bundledTitles: Set = [
            Region.canada.localizedName,
            Region.europeanUnion.localizedName,
        ]
        let usTitles = Set(outlines.map(\.title)).subtracting(bundledTitles)
        #expect(usTitles.count == 52)
    }

    @Test func source_includesCanadaAndEU() async throws {
        let outlines = try await RegionGeometryCatalog.outlines(for: .source, attributor: .all)
        let canada = outlines.filter { $0.region == .canada }
        let eu = outlines.filter { $0.region == .europeanUnion }
        #expect(!canada.isEmpty)
        #expect(canada.allSatisfy { $0.title == Region.canada.localizedName })
        #expect(!eu.isEmpty)
        #expect(eu.allSatisfy { $0.title == Region.europeanUnion.localizedName })
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
            attributor: trackedFour,
        )
        let box = try #require(BoundingBox.enclosing(outlines))
        for outline in outlines {
            for coordinate in outline.coordinates {
                #expect(box.contains(coordinate))
            }
        }
    }

    @Test func boundingBox_ofEmptyOutlinesIsNil() {
        #expect(BoundingBox.enclosing([] as [RegionOutline]) == nil)
    }

    // MARK: - Errors

    @Test func missingResourceErrorNamesTheFile() {
        let error = RegionGeometryError.missingResource("us-states")
        // `errorDescription` (LocalizedError) is what the viewer renders;
        // it must name the file, not fall back to the generic message.
        #expect(error.errorDescription?.contains("us-states.geojson") == true)
        #expect(error.localizedDescription.contains("us-states.geojson"))
    }

    @Test func emptyResourceErrorNamesTheFile() {
        let error = RegionGeometryError.emptyResource("us-CA")
        #expect(error.errorDescription?.contains("us-CA.geojson") == true)
        #expect(error.localizedDescription.contains("us-CA.geojson"))
    }
}
