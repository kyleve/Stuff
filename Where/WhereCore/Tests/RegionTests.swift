import Testing
import WhereCore

struct RegionTests {
    // MARK: - localizedName

    @Test func localizedName_returnsEnglishStringForEachCase() {
        #expect(Region.california.localizedName == "California")
        #expect(Region.newYork.localizedName == "New York")
        #expect(Region.canada.localizedName == "Canada")
        #expect(Region.europeanUnion.localizedName == "European Union")
        #expect(Region.other.localizedName == "Other")
    }

    // MARK: - geometrySource

    @Test func california_isUSStateFeature() {
        #expect(Region.california.geometrySource == .usStateFeature(name: "California"))
    }

    @Test func newYork_isUSStateFeature() {
        #expect(Region.newYork.geometrySource == .usStateFeature(name: "New York"))
    }

    @Test func canada_isBundledFile() {
        #expect(Region.canada.geometrySource == .bundledFile)
    }

    @Test func europeanUnion_isBundledFile() {
        #expect(Region.europeanUnion.geometrySource == .bundledFile)
    }

    @Test func other_hasNoGeometry() {
        #expect(Region.other.geometrySource == .none)
    }

    /// Every non-`.other` region must declare a real geometry source, so a
    /// newly added `Region` case can't silently ship with no polygons and
    /// attribute everything to `.other`.
    @Test func everyRegionExceptOtherHasGeometry() {
        for region in Region.allCases where region != .other {
            #expect(region.geometrySource != .none, "\(region.rawValue) has no geometry source")
        }
    }
}
