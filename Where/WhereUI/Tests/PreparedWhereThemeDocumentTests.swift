import Testing
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

@MainActor
struct PreparedWhereThemeDocumentTests {
    @Test func missingPreparedResourcesRejectsWholeTheme() throws {
        let theme = try LegacyThemeFixtures.prepare(.christmas)
        #expect(throws: ViewDocumentView.ResourceError.self) {
            try PreparedWhereThemeDocument(
                validated: theme.validated,
                assets: .init(images: [:], symbols: [:]),
            )
        }
        #expect(theme.componentArtwork[.locations]?.isEmpty == true)
        #expect(theme.componentArtwork[.regularCard]?.count == 1)
        #expect(theme.componentArtwork[.compactCard]?.count == 1)
    }
}
