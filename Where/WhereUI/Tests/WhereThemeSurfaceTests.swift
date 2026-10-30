import BroadwayCore
import Foundation
import SwiftUI
import Testing
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

struct WhereThemeSurfaceTests {
    @Test(arguments: [
        ViewColorDescriptor.semantic(.secondary),
        .semantic(.accent),
        .rgba(red: 1, green: 0, blue: 0, alpha: 0.5),
    ])
    func matteFillRejectsColorsWithoutOpaqueAlpha(_ color: ViewColorDescriptor) throws {
        let surface = WhereThemeMatteSurface(
            fill: .init(base: .constant(color), tintMix: 0),
            outline: nil,
            shadow: nil,
            pressedTintOpacity: nil,
        )
        #expect(throws: WhereThemeValidationError.self) {
            try surface.resolve(
                mode: .light,
                appearance: .init(background: .white, dimensionScales: [:]),
                base: WhereStylesheet.default.card.elsewherePaper.surface,
            )
        }
    }

    @Test(arguments: [
        ViewColorDescriptor.semantic(.primary),
        .semantic(.background),
        .rgba(red: 1, green: 0, blue: 0, alpha: 1),
    ])
    func matteFillAcceptsOpaqueColors(_ color: ViewColorDescriptor) throws {
        let surface = WhereThemeMatteSurface(
            fill: .init(base: .constant(color), tintMix: 0),
            outline: nil,
            shadow: nil,
            pressedTintOpacity: nil,
        )
        let appearance = ViewDocumentAppearance(background: .white, dimensionScales: [:])
        let result = try surface.resolve(
            mode: .light,
            appearance: appearance,
            base: WhereStylesheet.default.card.elsewherePaper.surface,
        )
        #expect(result.fill.base == appearance.color(color))
    }

    @MainActor
    @Test func sparseMattePatchInheritsFlatFillAndProtectsContrast() throws {
        var patch = WhereThemeMatteSurface()
        patch.shadow = .init()
        patch.shadow?.radius = 0
        patch.outline = .init()
        patch.outline?.opacity = 0
        var appearance = WhereThemeAppearance()
        appearance.card = .init()
        appearance.card?.regular = .init()
        appearance.card?.regular?.surface = .constant(.matte(patch))
        var traits = BTraits.system
        traits.accessibility = .init(isDarkerSystemColorsEnabled: true)
        let base = try resolveTheme(
            themeDocument(appearance: .init(), fallback: .flat),
            traits: traits,
        )
        let result = try resolveTheme(
            themeDocument(appearance: appearance, fallback: .flat),
            traits: traits,
        )
        guard case let .matte(original) = base.card.regular.surface,
              case let .matte(changed) = result.card.regular.surface
        else {
            Issue.record("Expected matte surfaces")
            return
        }
        #expect(changed.fill == original.fill)
        #expect(changed.outline == original.outline)
        #expect(changed.shadow.radius == 0)
    }

    @Test func matteSurfaceRoundTripsAndResolvesExplicitMode() throws {
        let value = WhereThemeMatteSurface(
            fill: .init(
                base: .modes(.init(
                    light: .rgba(red: 1, green: 1, blue: 1, alpha: 1),
                    dark: .rgba(red: 0, green: 0, blue: 0, alpha: 1),
                )),
                tintMix: 0.5,
            ),
            outline: .init(opacity: 0.4, width: 1),
            shadow: .init(
                color: .constant(.rgba(red: 0, green: 0, blue: 0, alpha: 0.2)),
                radius: 6,
                offsetY: 3,
            ),
            pressedTintOpacity: 0.1,
        )
        let surface = WhereThemeSurface.matte(value)
        #expect(try JSONDecoder().decode(
            WhereThemeSurface.self,
            from: JSONEncoder().encode(surface),
        ) == surface)
        let base = WhereStylesheet.default.card.elsewherePaper.surface
        let appearance = ViewDocumentAppearance(background: .white, dimensionScales: [:])
        let light = try value.resolve(mode: .light, appearance: appearance, base: base)
        let dark = try value.resolve(mode: .dark, appearance: appearance, base: base)
        #expect(light.fill.base != dark.fill.base)
        #expect(light.fill.tintMix == 0.5)
        #expect(light.outline == dark.outline)
        var invalid = value
        invalid.outline?.opacity = 2
        #expect(throws: WhereThemeValidationError.self) { try invalid.resolve(
            mode: .light,
            appearance: appearance,
            base: base,
        ) }
    }
}
