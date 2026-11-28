import BroadwayCore
import SwiftUI
import Testing
@testable import WhereUI

struct AdaptivePaneStyleTests {
    @Test func defaultsRequireEnoughRoomForReadableDetailAndControls() {
        let style = WhereStylesheet.default.adaptivePane
        #expect(style.panes == .single)
        #expect(style.minimumDetailWidth == 320)
        #expect(style.minimumControlsWidth == 280)
        #expect(style.minimumPaneHeight == 220)
        #expect(style.selection.cornerRadius == 8)
        #expect(style.selection.borderWidth == 2)
    }

    @MainActor
    @Test func selectionDarkensTheRegionTintInLightModeAndLightensItInDarkMode() throws {
        let tint = Color(red: 0.8, green: 0.4, blue: 0.2)
        let original = tint.resolve(in: EnvironmentValues())
        var context = BContext(traits: .system)
        for mode in [BMode.light, .dark] {
            context.traitOverrides.mode = mode
            let selection = try context.stylesheets.get(WhereStylesheet.self).adaptivePane.selection
            let border = selection.borderTint.apply(to: tint).resolve(in: EnvironmentValues())
            #expect(border.red > border.green && border.green > border.blue)
            #expect(mode == .light ? border.green < original.green : border.green > original.green)
        }
    }
}
