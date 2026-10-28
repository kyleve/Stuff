import BroadwayCore
import BroadwayUI
import SwiftUI

/// Flyover's reusable presentation tokens, resolved through Broadway.
struct FlyoverStylesheet: BStylesheet {
    var canvas = CanvasStyle()
    var layout = LayoutStyle()
    var group = GroupStyle()
    var depthBand = DepthBandStyle()
    var screen = ScreenStyle()
    var screenContent = ScreenContentStyle()
    var screenControls = ScreenControlsStyle()
    var routeSummary = RouteSummaryStyle()
    var controlBar = ControlBarStyle()
    var focused = FocusedStyle()
    var list = ListStyle()
    var connector = ConnectorStyle()

    init() {}

    init(context: SlicingContext) throws {
        if context.traits.accessibility.isReduceTransparencyEnabled {
            group.fillOpacity = 1
            screen.shadow.opacity = 0
        }
    }

    static let `default` = FlyoverStylesheet()
}

extension FlyoverStylesheet {
    struct CanvasStyle: Equatable {
        var background = Color(.systemGroupedBackground)
        var overlayPadding: CGFloat = 16
        var overlayControlSize = ControlSize.small
        var framingInset: CGFloat = 16
    }

    struct LayoutStyle: Equatable {
        var cardSize = CGSize(width: 300, height: 650)
        var horizontalSpacing: CGFloat = 100
        var verticalSpacing: CGFloat = 90
        var maximumAutomaticRowsPerColumn = 4
        var depthBandHorizontalInset: CGFloat = 20
        var depthBandTopInset: CGFloat = 12
        var depthBandBottomInset: CGFloat = 24
        var groupPadding: CGFloat = 60
        var groupSpacing: CGFloat = 120
        var canvasPadding: CGFloat = 40
        var groupHeaderHeight: CGFloat = 44
    }

    struct GroupStyle: Equatable {
        var cornerRadius: CGFloat = 28
        var fill = Color(.systemBackground)
        var fillOpacity: Double = 0.75
        var strokeWidth: CGFloat = 2
        var titleFont = Font.title2.bold()
        var titlePadding: CGFloat = 20
    }

    struct DepthBandStyle: Equatable {
        var labelFont = Font.caption.bold()
        var labelColor = Color.secondary
        var labelLeadingPadding: CGFloat = 10
        var labelSpacing: CGFloat = 6
        var ruleColor = Color.secondary
        var ruleOpacity: Double = 0.24
        var ruleWidth: CGFloat = 1
    }

    struct ScreenStyle: Equatable {
        var contentMaximumHeight: CGFloat = 440
        var contentShade = Color.black
        var contentShadeOpacity: Double = 0.08
        var background = Color(.systemBackground)
        var cornerRadius: CGFloat = 22
        var borderWidth: CGFloat = 1
        var shadow = Shadow()
        var header = Header()
        var placeholder = Placeholder()

        struct Shadow: Equatable {
            var color = Color.black
            var opacity: Double = 0.12
            var radius: CGFloat = 12
            var offsetY: CGFloat = 5
        }

        struct Header: Equatable {
            var font = Font.headline
            var padding: CGFloat = 12
        }

        struct Placeholder: Equatable {
            var spacing: CGFloat = 12
            var iconFont = Font.largeTitle
            var titleFont = Font.headline
            var messageFont = Font.caption
            var messageMaximumWidth: CGFloat = 220
            var controlSize = ControlSize.small
        }
    }

    struct ScreenContentStyle: Equatable {
        var overviewMaximumSize = CGSize(width: 260, height: 430)
        var cornerRadius: CGFloat = 18
    }

    struct ScreenControlsStyle: Equatable {
        var spacing: CGFloat = 8
        var padding: CGFloat = 12
        var maximumHeight: CGFloat = 126
        var controlSize = ControlSize.small
    }

    struct RouteSummaryStyle: Equatable {
        var spacing: CGFloat = 8
        var font = Font.caption2
        var horizontalPadding: CGFloat = 12
        var bottomPadding: CGFloat = 10
        var height: CGFloat = 34
    }

    struct ControlBarStyle: Equatable {
        var wideSpacing: CGFloat = 16
        var wideViewModeWidth: CGFloat = 220
        var wideZoomWidth: CGFloat = 240
        var compactSpacing: CGFloat = 12
        var compactViewModeWidth: CGFloat = 160
        var compactZoomWidth: CGFloat = 180
        var focusedSpacing: CGFloat = 16
        var focusedControlMinimumWidth: CGFloat = 160
        var horizontalPadding: CGFloat = 16
        var verticalPadding: CGFloat = 10
        var controlSize = ControlSize.small
    }

    struct FocusedStyle: Equatable {
        var contentPadding: CGFloat = 24
    }

    struct ListStyle: Equatable {
        var groupSpacing: CGFloat = 40
        var contentPadding: CGFloat = 32
        var groupTitleFont = Font.title.bold()
    }

    struct ConnectorStyle: Equatable {
        var curvature: CGFloat = 0.45
        var minimumControlOffset: CGFloat = 40
        var lineWidth: CGFloat = 3
        var modalDash: [CGFloat] = [12, 8]
        var arrowWidth: CGFloat = 12
        var arrowHalfHeight: CGFloat = 7
        var labelFont = Font.caption.bold()
        var labelOffsetY: CGFloat = 12
        var pushColor = Color.blue
        var modalColor = Color.purple
    }
}

extension EnvironmentValues {
    var flyoverStylesheet: FlyoverStylesheet {
        bContext.stylesheet(FlyoverStylesheet.self, fallback: .default)
    }
}
