@testable import PortholeKitUI
import SwiftUI
import Testing

struct PortholeStylesheetTests {
    @Test func defaultTokensArePinned() {
        let sheet = PortholeStylesheet.default
        #expect(sheet.spacing.small == 8)
        #expect(sheet.spacing.medium == 16)
        #expect(sheet.spacing.large == 24)
        #expect(sheet.code.digitTracking == 6)
        #expect(sheet.code.verticalPadding == 12)
        #expect(sheet.palette.advertising == .green)
        #expect(sheet.palette.sessionBadge == .blue)
    }

    @Test func environmentFallsBackToDefaultWithoutAContext() {
        #expect(EnvironmentValues().stylesheet == .default)
    }
}
