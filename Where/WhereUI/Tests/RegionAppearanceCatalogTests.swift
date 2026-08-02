import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// The picker exposes every stored color while id-derived fallback appearances
/// remain stable as new choices are added.
struct RegionAppearanceCatalogTests {
    @Test func selectorIncludesEveryColorToken() {
        #expect(RegionAppearanceCatalog.colors == RegionColorToken.allCases)
    }

    @Test func expandedSelectorDoesNotRecolorExistingDefaults() throws {
        let texas = try #require(Region(rawValue: "us-TX"))
        #expect(RegionAppearanceCatalog.defaultAppearance(for: texas).color == .pink)
    }

    @Test func lightSwatchesUseDarkSelectionGlyphs() {
        #expect(RegionColorToken.gold.selectionForeground == .black)
        #expect(RegionColorToken.lime.selectionForeground == .black)
        #expect(RegionColorToken.silver.selectionForeground == .black)
        #expect(RegionColorToken.coral.selectionForeground == .white)
    }
}
