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
        #expect(style.selection.border == Color.accentColor)
    }
}
