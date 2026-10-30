import BroadwayCore
import Foundation
import Testing
import ViewDocumentCore
import WhereCore
@testable import WhereUI

@MainActor
func themeDocument(
    appearance: WhereThemeAppearance,
    fallback: WhereThemeDocument.Fallback,
) -> WhereThemeDocument {
    .init(
        schemaVersion: 1,
        id: .init(rawValue: "test"),
        fallback: fallback,
        appearance: appearance,
        layers: .init(),
    )
}

@MainActor
func resolveTheme(_ document: WhereThemeDocument, traits: BTraits) throws -> WhereStylesheet {
    let validated = try ValidatedWhereThemeDocument(
        document: document,
        resources: .init(images: [], symbols: []),
    )
    var themes = BThemes()
    themes[WhereDocumentTheme.self] = .init(document: validated)
    return BContext(traits: traits, themes: themes).stylesheet(
        WhereStylesheet.self,
        fallback: .default,
    )
}

@MainActor
func verifyThemePatch<Value: Equatable>(
    json: String,
    keyPath: WritableKeyPath<WhereStylesheet, Value>,
    replacement: Value,
) throws {
    let patch = try JSONDecoder().decode(WhereThemeAppearance.self, from: Data(json.utf8))
    #expect(try JSONDecoder()
        .decode(WhereThemeAppearance.self, from: JSONEncoder().encode(patch)) == patch)
    var actual = WhereStylesheet.default
    var expected = actual
    expected[keyPath: keyPath] = replacement
    try patch.apply(
        to: &actual,
        traits: .system,
        appearance: .init(background: .white, dimensionScales: [:]),
        path: "appearance",
    )
    #expect(actual == expected)
}
