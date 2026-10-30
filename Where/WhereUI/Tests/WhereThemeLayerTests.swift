import SwiftUI
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeLayerTests {
    @Test func documentSlotsPreserveHostBounds() throws {
        let theme = try WhereThemeExamples.christmas.prepare()
        let host = Color.white.frame(width: 90, height: 60)
            .whereThemeBackground(.regularCardBackground, cornerRadius: 12)
            .whereThemeOverlay(.regularCardOverlay, cornerRadius: 12)
            .whereBroadwayRoot(themeDocument: theme)
        let image = try #require(ImageRenderer(content: host).uiImage)
        #expect(image.size == CGSize(width: 90, height: 60))
    }
}
