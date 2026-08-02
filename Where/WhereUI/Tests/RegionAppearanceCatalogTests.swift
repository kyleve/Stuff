import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// The picker and id-derived fallback appearances share one complete palette.
struct RegionAppearanceCatalogTests {
    @Test func selectorIncludesEveryColorToken() {
        #expect(RegionAppearanceCatalog.colors == RegionColorToken.allCases)
    }

    @Test func idDerivedDefaultsUseExpandedColors() throws {
        let texas = try #require(Region(rawValue: "us-TX"))
        #expect(RegionAppearanceCatalog.defaultAppearance(for: texas).color == .charcoal)
    }

    @Test func lightSwatchesUseDarkSelectionGlyphs() {
        #expect(RegionColorToken.gold.selectionForeground == .black)
        #expect(RegionColorToken.lime.selectionForeground == .black)
        #expect(RegionColorToken.silver.selectionForeground == .black)
        #expect(RegionColorToken.coral.selectionForeground == .white)
    }
}
