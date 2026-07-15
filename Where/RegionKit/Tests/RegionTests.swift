import Foundation
import RegionKit
import Testing

struct RegionTests {
    // MARK: - localizedName

    @Test func localizedName_resolvesLocalizedRegions() {
        #expect(Region.california.localizedName == "California")
        #expect(Region.newYork.localizedName == "New York")
        #expect(Region.canada.localizedName == "Canada")
        #expect(Region.europeanUnion.localizedName == "European Union")
        #expect(Region.other.localizedName == "Other")
    }

    @Test func localizedName_fallsBackToManifestNameForUnlocalizedRegions() throws {
        // Texas has no string-catalog entry, so its name comes from the manifest.
        let texas = try #require(Region(rawValue: "us-TX"))
        #expect(texas.localizedName == "Texas")
    }

    // MARK: - Stable ids

    @Test func conveniences_useStableIDs() {
        #expect(Region.california.rawValue == "us-CA")
        #expect(Region.newYork.rawValue == "us-NY")
        #expect(Region.canada.rawValue == "canada")
        #expect(Region.europeanUnion.rawValue == "european-union")
        #expect(Region.other.rawValue == "other")
    }

    // MARK: - Failable init

    @Test func initRawValue_acceptsCatalogRegionsAndOther() {
        #expect(Region(rawValue: "us-CA") == .california)
        #expect(Region(rawValue: "us-TX")?.rawValue == "us-TX")
        #expect(Region(rawValue: "other") == .other)
    }

    @Test func initRawValue_rejectsUnknownIDs() {
        #expect(Region(rawValue: "not-a-region") == nil)
        // The former enum's raw values are no longer valid ids.
        #expect(Region(rawValue: "california") == nil)
    }

    // MARK: - Codable

    @Test func codable_roundTripsThroughID() throws {
        let texas = try #require(Region(rawValue: "us-TX"))
        let regions: [Region] = [.california, .canada, .other, texas]
        let data = try JSONEncoder().encode(regions)
        let decoded = try JSONDecoder().decode([Region].self, from: data)
        #expect(decoded == regions)
    }

    // MARK: - Catalog membership

    @Test func catalog_containsEveryUSStatePlusDCAndPRPlusBlocs() {
        // 50 states + DC + PR + Canada + European Union.
        #expect(RegionCatalog.shared.all.count == 54)
        #expect(RegionCatalog.shared.all.contains(.california))
        #expect(RegionCatalog.shared.all.contains(.newYork))
        #expect(RegionCatalog.shared.all.contains(.canada))
        #expect(RegionCatalog.shared.all.contains(.europeanUnion))
    }

    @Test func allCases_isCatalogOrderThenOther() {
        #expect(Region.allCases == RegionCatalog.shared.all + [.other])
        #expect(Region.allCases.last == .other)
        // `.other` is a sentinel, never a catalog entry.
        #expect(!RegionCatalog.shared.all.contains(.other))
    }
}
