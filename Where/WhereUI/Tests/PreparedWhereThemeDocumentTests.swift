import Testing
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

@MainActor
struct PreparedWhereThemeDocumentTests {
    @Test func missingPreparedResourcesRejectsWholeTheme() throws {
        let theme = try WhereThemeExamples.christmas.prepare()
        #expect(throws: ViewDocumentView.ResourceError.self) {
            try PreparedWhereThemeDocument(
                validated: theme.validated,
                assets: .init(images: [:], symbols: [:]),
            )
        }
        #expect(theme.layers[.locationsBackground]?.isEmpty == true)
        #expect(theme.layers[.regularCardOverlay]?.count == 1)
        #expect(theme.layers[.compactCardOverlay]?.count == 1)
    }
}
