import SwiftUI
import Testing
@testable import WhereUI

struct AdaptiveHistoryStyleTests {
    @Test func defaultsRequireEnoughRoomForReadableHistoryAndControls() {
        let style = WhereStylesheet.default.adaptiveHistory
        #expect(style.panes == .single)
        #expect(style.minimumHistoryWidth == 320)
        #expect(style.minimumControlsWidth == 280)
        #expect(style.minimumPaneHeight == 220)
        #expect(style.selection.cornerRadius == 8)
        #expect(style.selection.borderWidth == 2)
        #expect(style.selection.border == Color.accentColor)
    }
}
