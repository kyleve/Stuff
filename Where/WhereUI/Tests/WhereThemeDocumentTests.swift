import BroadwayCore
import Foundation
import Testing
import ViewDocumentCore
import WhereCore
@testable import WhereUI

@MainActor
struct WhereThemeDocumentTests {
    @Test func sparseJSONRoundTripsAndPreservesExplicitZero() throws {
        let json = Data(
            #"{"schemaVersion":1,"id":"example","fallback":"flat","appearance":{"card":{"regular":{"cornerRadius":{"constant":{"_0":0}}}}},"layers":{}}"#
                .utf8,
        )
        let decoded = try JSONDecoder().decode(WhereThemeDocument.self, from: json)
        #expect(decoded.id.rawValue == "example")
        #expect(decoded.fallback == .flat)
        #expect(decoded.appearance.card?.regular?.cornerRadius == .constant(0))
        #expect(decoded.appearance.card?.compact == nil)
        #expect(try JSONDecoder().decode(
            WhereThemeDocument.self,
            from: JSONEncoder().encode(decoded),
        ) == decoded)
    }

    @Test func emptyDocumentMatchesFallbackAcrossModesAndAccessibility() throws {
        for fallback: WhereThemeDocument.Fallback in [.standard, .flat] {
            for mode: BMode in [.light, .dark] {
                for accessibility in [
                    BAccessibility(),
                    .init(isReduceMotionEnabled: true),
                    .init(isReduceTransparencyEnabled: true),
                    .init(isDarkerSystemColorsEnabled: true),
                    .init(shouldDifferentiateWithoutColor: true),
                ] {
                    var traits = BTraits.system
                    traits.mode = mode
                    traits.contentSizeCategory = .accessibilityExtraExtraExtraLarge
                    traits.accessibility = accessibility
                    let original = BContext(
                        traits: traits,
                        themes: WhereThemes.current(theme: fallback.theme),
                    ).stylesheet(WhereStylesheet.self, fallback: .default)
                    let resolved = try resolveTheme(
                        themeDocument(appearance: .init(), fallback: fallback),
                        traits: traits,
                    )
                    #expect(resolved == original)
                }
            }
        }
    }
}
