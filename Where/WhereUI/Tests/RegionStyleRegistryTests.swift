import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// `RegionStyle.style(for:)` resolves a picked appearance through
/// `RegionStyleRegistry`, falling back to the deterministic default look.
struct RegionStyleRegistryTests {
    @Test func pickedAppearanceWinsOverFallback() {
        let registry = RegionStyleRegistry()
        let look = RegionAppearance(color: .pink, emoji: "🎸", symbolName: "star.fill")
        registry.replaceAll([.california: look])

        #expect(registry.appearance(for: .california) == look)
        // A region with no entry resolves to nil (the caller uses its fallback).
        #expect(registry.appearance(for: .newYork) == nil)

        let style = RegionStyle(look)
        #expect(style.emoji == "🎸")
        #expect(style.symbolName == "star.fill")
    }

    @Test func replaceAllFromPrimaryRegionsKeepsOnlyResolvedLooks() {
        let registry = RegionStyleRegistry()
        let look = RegionAppearance(color: .teal, emoji: "🌊", symbolName: "water.waves")
        registry.replaceAll(from: [
            PrimaryRegion(region: .california, appearance: look, order: 0),
            PrimaryRegion(region: .newYork, appearance: nil, order: 1),
        ])

        #expect(registry.appearance(for: .california) == look)
        #expect(registry.appearance(for: .newYork) == nil)
    }

    @Test func replaceAllRemovesStalePicks() {
        let registry = RegionStyleRegistry()
        let look = RegionAppearance(color: .red, emoji: "🍁", symbolName: "leaf.fill")
        registry.replaceAll([.canada: look])
        // A wholesale swap drops a region that's no longer primary.
        registry.replaceAll([:])
        #expect(registry.appearance(for: .canada) == nil)
    }

    @Test func defaultAppearanceMatchesSharedCatalog() {
        // The customization pre-fill and the RegionStyle fallback share one
        // source, so a region with no pick renders its catalog default.
        let expected = RegionAppearanceCatalog.defaultAppearance(for: .california)
        let fallback = RegionStyle.fallbackStyle(for: .california)
        #expect(fallback.emoji == expected.emoji)
        #expect(fallback.symbolName == expected.symbolName)
    }
}
