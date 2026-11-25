import Foundation
@testable import RegionKit
import Testing

enum RegionHierarchyFixture {
    /// Canonical order of the original US tracking choices, alphabetical by name.
    static let usIDs = """
    AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA PR RI SC SD TN TX UT VT VA WA WV WI WY
    """.split(separator: " ").map { "us-" + $0 }

    static func catalog() throws -> RegionCatalog {
        let states = usIDs.map { id in
            let kind = ["us-DC": "federalDistrict", "us-PR": "territory"][id] ?? "state"
            return row(id, kind, parent: "united-states")
        }
        return try decode(states + [
            row("ca-ON", "province", parent: "canada"),
            row("united-states", "country", loggable: false),
            row("canada", "country", loggable: false),
            row("european-union", "bloc"),
        ])
    }

    static func row(
        _ id: String,
        _ kind: String,
        loggable: Bool = true,
        parent: String? = nil,
    ) -> [String: Any] {
        var row: [String: Any] = [
            "id": id,
            "name": id,
            "kind": kind,
            "isLoggable": loggable,
        ]
        if kind != "country" { row["geometryFile"] = "fixtures/\(id).geojson" }
        row["parentID"] = parent
        return row
    }

    static func decode(_ rows: [[String: Any]]) throws -> RegionCatalog {
        try RegionCatalog(manifest: JSONSerialization.data(withJSONObject: rows))
    }
}

struct RegionCatalogTests {
    @Test func hierarchyFollowsExplicitRelationshipsInManifestOrder() throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let california = try #require(catalog.node(for: .california))
        let us = try #require(catalog.parent(of: california))
        #expect(us.id.rawValue == "united-states")
        #expect(us.kind == .country)
        #expect(us.region == nil)
        #expect(catalog.parent(of: us) == nil)
        #expect(catalog.children(of: us).map(\.id.rawValue) == RegionHierarchyFixture.usIDs)
        #expect(catalog.children(of: california).isEmpty)
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
        let ontario = try #require(catalog.node(id: .init(rawValue: "ca-ON")))
        #expect(catalog.children(of: canada) == [ontario])
        #expect(catalog.parent(of: ontario) == canada)
        #expect(ontario.kind == .province)
    }

    @Test(arguments: ["united-states", "canada"])
    func loggingEligibilityFiltersEveryRegionLookup(countryID: String) throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let node = try #require(catalog.node(id: .init(rawValue: countryID)))
        let region = Region(unchecked: countryID)
        #expect(node.region == nil)
        #expect(node.geometryFile == nil)
        #expect(!catalog.contains(id: countryID))
        #expect(catalog.node(for: region) == nil)
        #expect(catalog.entry(for: region) == nil)
        #expect(!catalog.all.contains(region))
        #expect(!catalog.entries.contains { $0.region == region })
        #expect(catalog.node(for: .other) == nil)
        #expect(catalog.node(id: .init(rawValue: "unknown")) == nil)
    }

    @Test func bundledUSOrderKindsAndStoredIDsAreStable() throws {
        let catalog = RegionCatalog.shared
        #expect(catalog.all.map(\.rawValue).filter { $0.hasPrefix("us-") } == RegionHierarchyFixture
            .usIDs)
        #expect(catalog.node(for: .california)?.kind == .state)
        #expect(catalog.node(id: .init(rawValue: "us-DC"))?.kind == .federalDistrict)
        #expect(catalog.node(id: .init(rawValue: "us-PR"))?.kind == .territory)
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
        #expect(canada.kind == .country)
        #expect(catalog.parent(of: canada) == nil)
        let eu = try #require(catalog.node(for: .europeanUnion))
        #expect(eu.kind == .bloc)
        #expect(catalog.parent(of: eu) == nil)
        #expect(Region(rawValue: "united-states") == nil)
        for id in ["us-CA", "ca-ON", "european-union", "other", "unknown-historical-id"] {
            let bareString = Data("\"\(id)\"".utf8)
            let decoded = try JSONDecoder().decode(Region.self, from: bareString)
            #expect(try JSONEncoder().encode(decoded) == bareString)
        }
    }

    @Test func manifestRejectsBrokenGraphsAndInvalidMetadata() {
        let canada = RegionHierarchyFixture.row("canada", "country", loggable: false)
        let ontario = RegionHierarchyFixture.row("ca-ON", "province", parent: "canada")
        let us = RegionHierarchyFixture.row("united-states", "country", loggable: false)
        let invalid = [
            [us, us],
            [RegionHierarchyFixture.row("other", "state")],
            [ontario],
            [
                ontario,
                RegionHierarchyFixture.row("canada", "country", loggable: false, parent: "ca-ON"),
            ],
            [canada.merging(["isLoggable": true]) { _, new in new }, ontario],
            [canada, ontario.filter { $0.key != "geometryFile" }],
            [us.filter { $0.key != "isLoggable" }],
            [us.merging(["geometryFile": "us/united-states.twkb"]) { _, new in new }],
            [canada.merging(["geometryFile": "ca/canada.twkb"]) { _, new in new }, ontario],
            [RegionHierarchyFixture.row("state", "state", loggable: false)
                .filter { $0.key != "geometryFile" }],
            [canada, ontario.merging(["geometryFile": "../ca-ON.twkb"]) { _, new in new }],
            [canada, ontario.merging(["geometryFile": ""]) { _, new in new }],
        ]
        for rows in invalid {
            #expect(throws: DecodingError.self) { try RegionHierarchyFixture.decode(rows) }
        }
    }

    @Test(arguments: [
        "ca-ON.twkb",
        "/ca/ca-ON.twkb",
        "ca/../ca-ON.twkb",
        "ca//ca-ON.twkb",
        "ca/%2e%2e.twkb",
        "ca/ca-ON.txt"
    ])
    func manifestRejectsInvalidGeometryPaths(_ path: String) {
        var node = RegionHierarchyFixture.row("ca-ON", "province")
        node["geometryFile"] = path
        #expect(throws: DecodingError.self) { try RegionHierarchyFixture.decode([node]) }
    }

    @Test func bundlePreservesAllGeographicDirectories() throws {
        let catalog = RegionCatalog.shared
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
        let expected = Set(RegionHierarchyFixture.usIDs.map { "us/\($0).twkb" }
            + catalog.children(of: canada).map { "ca/\($0.id.rawValue).twkb" }
            + ["eu/european-union.geojson"])
        var paths: [String] = []
        for node in catalog.nodes {
            guard let path = node.geometryFile else { continue }
            let url = try #require(RegionCatalog.geometryURL(for: node))
            #expect(url.pathComponents.suffix(3).joined(separator: "/") == "regions/\(path)")
            #expect(try url.checkResourceIsReachable())
            paths.append(path)
        }
        #expect(paths.count == 66)
        #expect(Set(paths) == expected)
    }
}
