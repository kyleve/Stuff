import BroadwayCore
import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeAppearanceTests {
    @Test nonisolated func boxedGroupsKeepBackgroundCodingBoundedAndCopiesIndependent() throws {
        #expect(MemoryLayout<WhereThemeAppearance>.size <= 512)
        #expect(MemoryLayout<WhereThemeAppearance.CardStyles>.size <= 1024)
        #expect(MemoryLayout<WhereThemeAppearance.CardStyle>.size <= 2048)
        let original = try WhereBundledThemeDefinitions.resolved(.standard).appearance
        let encoded = try JSONEncoder().encode(original)
        var decoded = try JSONDecoder().decode(WhereThemeAppearance.self, from: encoded)
        #expect(decoded == original)
        decoded.card?.regular?.cornerRadius = .constant(41)
        #expect(original.card?.regular?.cornerRadius != .constant(41))
        #expect(decoded.card?.regular?.cornerRadius == .constant(41))
        decoded.card = nil
        #expect(throws: WhereThemeValidationError.self) {
            try decoded.requireComplete(path: "appearance")
        }
    }

    @Test func explicitZeroPreservesUnrelatedComponentState() throws {
        var parent = try WhereBundledThemeDefinitions.resolved(.standard).appearance
        parent.card?.regular?.padding = .constant(39)
        var patch = WhereThemeAppearance()
        patch.locationWelcome = .init()
        patch.locationWelcome?.glow = .init()
        patch.locationWelcome?.glow?.opacity = .constant(0)
        let result = patch.inheriting(parent)
        #expect(result.locationWelcome?.glow?.opacity == .constant(0))
        #expect(result.card == parent.card)
        #expect(result.locationWelcome?.cornerRadius == parent.locationWelcome?.cornerRadius)
        #expect(result.locationForecast == parent.locationForecast)
    }

    @Test func emptyAppearanceEncodesAsEmptyObjectAndPreservesNativeState() throws {
        let patch = WhereThemeAppearance()
        #expect(try String(decoding: JSONEncoder().encode(patch), as: UTF8.self) == "{}")
        var actual = WhereStylesheet.default
        let expected = actual
        try patch.apply(
            to: &actual,
            traits: .system,
            appearance: .init(background: .white, dimensionScales: [:]),
            path: "appearance",
        )
        #expect(actual == expected)
    }
}
