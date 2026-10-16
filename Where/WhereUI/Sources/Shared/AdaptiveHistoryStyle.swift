import CoreGraphics
import SwiftUI

extension WhereStylesheet {
    /// Authored limits for two readable panes. Runtime geometry resolves the arrangement.
    struct AdaptiveHistoryStyle: Equatable {
        enum Panes: Equatable {
            case single
            case multiple
        }

        var panes = Panes.single
        /// Point widths needed for the month grid and location/settings controls.
        var minimumHistoryWidth: CGFloat = 320
        var minimumControlsWidth: CGFloat = 280
        /// Point height needed for independently scrollable history and controls.
        var minimumPaneHeight: CGFloat = 220

        var selection = Selection()

        struct Selection: Equatable {
            var cornerRadius: CGFloat = 8
            var borderWidth: CGFloat = 2
            var border = Color.accentColor
        }
    }
}
