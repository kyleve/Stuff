import RegionKit
import SwiftUI
import Testing
@testable import WhereCore
@testable import WhereUI

/// The picker and id-derived fallback appearances share one complete palette.
struct RegionAppearanceCatalogTests {
    @Test func selectorIncludesEveryColorToken() {
        #expect(RegionAppearanceCatalog.colors == RegionColorToken.allCases)
    }

    @Test func idDerivedDefaultsHaveStableAssignments() throws {
        // Fixed expectations also catch accidentally using Swift's randomized
        // hash. NV, CO, and FL collided under the former character-sum fallback.
        let expected: [Region: RegionColorToken] = try [
            #require(Region(rawValue: "us-NV")): .orange,
            #require(Region(rawValue: "us-OR")): .charcoal,
            #require(Region(rawValue: "us-CO")): .purple,
            #require(Region(rawValue: "us-FL")): .teal,
            #require(Region(rawValue: "us-TX")): .brown,
            #require(Region(rawValue: "us-WA")): .mint,
        ]
        for (region, color) in expected {
            #expect(RegionAppearanceCatalog.defaultAppearance(for: region).color == color)
        }
    }

    @Test func catalogDefaultsSpanTheSelectablePalette() {
        let colors = Region.allCases.map {
            RegionAppearanceCatalog.defaultAppearance(for: $0).color
        }
        #expect(Set(colors) == Set(RegionAppearanceCatalog.colors))
    }

    @Test func bespokeDefaultsKeepTheirEstablishedColors() {
        let expected: [Region: RegionColorToken] = [
            .california: .orange,
            .newYork: .indigo,
            .europeanUnion: .blue,
            .other: .teal,
        ]
        for (region, color) in expected {
            #expect(RegionAppearanceCatalog.defaultAppearance(for: region).color == color)
        }
    }

    @Test func lightSwatchesUseDarkSelectionGlyphs() {
        #expect(RegionColorToken.gold.selectionForeground == .black)
        #expect(RegionColorToken.lime.selectionForeground == .black)
        #expect(RegionColorToken.silver.selectionForeground == .black)
    }

    @Test func coralKeepsItsLightColorAndLightensOnDarkSurfaces() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        let coral = RegionColorToken.coral
        let lightFill = coral.color.resolve(in: light)
        let darkFill = coral.color.resolve(in: dark)
        #expect(lightFill == Color(red: 0.88, green: 0.26, blue: 0.22).resolve(in: light))
        #expect(darkFill.red > lightFill.red)
        #expect(darkFill.green > lightFill.green)
        #expect(darkFill.blue > lightFill.blue)
        #expect(coral.selectionForeground.resolve(in: light) == Color.white.resolve(in: light))
        #expect(coral.selectionForeground.resolve(in: dark) == Color.black.resolve(in: dark))
    }
}
