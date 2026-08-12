import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// `RegionStyleResolver.style(for:)` resolves a picked appearance, falling back
/// to the deterministic default look for regions the user hasn't customized.
struct RegionStyleResolverTests {
    @Test func pickedAppearanceWinsOverFallback() {
        let look = RegionAppearance(color: .pink, emoji: "🎸", symbolName: .starFill)
        let resolver = RegionStyleResolver(appearances: [.california: look])

        let california = resolver.style(for: .california)
        #expect(california.emoji == "🎸")
        #expect(california.symbol == .starFill)
        #expect(california.tint == RegionColorToken.pink.color)
    }

    @Test func unpickedRegionFallsBackToDefault() {
        let resolver = RegionStyleResolver(appearances: [:])
        let expected = RegionStyle.fallbackStyle(for: .newYork)
        let resolved = resolver.style(for: .newYork)
        #expect(resolved.emoji == expected.emoji)
        #expect(resolved.symbol == expected.symbol)
    }

    @Test func buildsFromPrimaryRegionsKeepingOnlyResolvedLooks() {
        let look = RegionAppearance(color: .teal, emoji: "🌊", symbolName: .waterWaves)
        let resolver = RegionStyleResolver(primaryRegions: [
            PrimaryRegion(region: .california, appearance: look, order: 0),
            PrimaryRegion(region: .newYork, appearance: nil, order: 1),
        ])

        #expect(resolver.style(for: .california).emoji == "🌊")
        // NY had no appearance → resolves to its fallback, not California's look.
        #expect(resolver.style(for: .newYork).emoji == RegionStyle.fallbackStyle(for: .newYork)
            .emoji)
    }

    @Test func defaultResolverIsAllFallback() {
        let resolver = RegionStyleResolver.default
        let expected = RegionStyle.fallbackStyle(for: .california)
        #expect(resolver.style(for: .california).symbol == expected.symbol)
    }

    @Test func defaultAppearanceMatchesSharedCatalog() {
        // The customization pre-fill and the fallback share one source, so a
        // region with no pick renders its catalog default.
        let expected = RegionAppearanceCatalog.defaultAppearance(for: .california)
        let fallback = RegionStyle.fallbackStyle(for: .california)
        #expect(fallback.emoji == expected.emoji)
        #expect(fallback.symbol == expected.symbolName.sfSymbol)
    }
}
