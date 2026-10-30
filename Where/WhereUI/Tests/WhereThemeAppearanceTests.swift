import BroadwayCore
import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeAppearanceTests {
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
