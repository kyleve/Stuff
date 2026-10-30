import SwiftUI
import Testing
@testable import WhereUI

@MainActor
struct WhereSecondaryContentStyleTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func builtInSecondaryStyleIsUnchanged(scheme: ColorScheme) throws {
        let actual = Rectangle().fill(.whereSecondary)
            .frame(width: 20, height: 20).environment(\.colorScheme, scheme)
        let expected = Rectangle().fill(.secondary)
            .frame(width: 20, height: 20).environment(\.colorScheme, scheme)
        #expect(try pixels(actual) == pixels(expected))
    }

    @Test func authoredInkDoesNotUseTheFaintHierarchicalSecondary() throws {
        let ink = Color(red: 0.3, green: 0.2, blue: 0.35)
        let actual = Rectangle().fill(.whereSecondary)
            .frame(width: 20, height: 20)
            .foregroundStyle(ink)
            .environment(\.whereThemeSecondaryInk, ink.opacity(0.85))
        let expected = Rectangle().fill(ink.opacity(0.85))
            .frame(width: 20, height: 20)
        #expect(try pixels(actual) == pixels(expected))
    }

    private func pixels(_ view: some View) throws -> Data {
        try #require(ImageRenderer(content: view).uiImage?.pngData())
    }
}
