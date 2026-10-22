import BroadwayCore
import BroadwayUI
import SwiftUI

struct ReviewStylesheet: BStylesheet {
    struct Browser: Equatable {
        var sidebarWidth: CGFloat = 320
        var minimumSidebarWidth: CGFloat = 260
        var caseListMaximumHeight: CGFloat = 220
        var cellWidth: CGFloat = 220
        var thumbnailHeight: CGFloat = 240
        var gap: CGFloat = 16
        var cornerRadius: CGFloat = 8
        var selectionOpacity: Double = 0.12
    }

    struct Details: Equatable {
        var rowPadding: CGFloat = 4
        var editorMinimumHeight: CGFloat = 180
    }

    struct Canvas: Equatable {
        var pinSize: CGFloat = 28
        var pinFill = Color.accentColor
        var outdatedFill = Color.orange
        var borderWidth: CGFloat = 1
        var selectedBorderWidth: CGFloat = 3
    }

    var browser = Browser()
    var details = Details()
    var canvas = Canvas()
    init() {}
    init(context: SlicingContext) throws {
        if context.traits.contentSizeCategory.isAccessibilitySize {
            browser.sidebarWidth = 400
            browser.cellWidth = 300
            canvas.pinSize = 40
        }
    }

    static let `default` = ReviewStylesheet()
}

extension EnvironmentValues {
    var reviewStyle: ReviewStylesheet {
        bContext.stylesheet(
            ReviewStylesheet.self,
            fallback: .default,
        )
    }
}
