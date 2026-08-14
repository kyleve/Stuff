import BroadwayCore
@testable import Flyover
import SwiftUI
import Testing

struct FlyoverStylesheetTests {
    private let style = FlyoverStylesheet.default

    @Test func canvasAndLayoutDefaults() {
        #expect(style.canvas.background == Color(.systemGroupedBackground))
        #expect(style.canvas.overlayPadding == 16)
        #expect(style.canvas.overlayControlSize == .small)
        #expect(style.canvas.framingInset == 16)

        #expect(style.layout.cardSize == CGSize(width: 300, height: 650))
        #expect(style.layout.horizontalSpacing == 100)
        #expect(style.layout.verticalSpacing == 90)
        #expect(style.layout.maximumAutomaticRowsPerColumn == 4)
        #expect(style.layout.groupPadding == 60)
        #expect(style.layout.groupSpacing == 120)
        #expect(style.layout.canvasPadding == 40)
        #expect(style.layout.groupHeaderHeight == 44)
    }

    @Test func groupAndScreenDefaults() {
        #expect(style.group.cornerRadius == 28)
        #expect(style.group.fill == Color(.systemBackground))
        #expect(style.group.fillOpacity == 0.75)
        #expect(style.group.strokeWidth == 2)
        #expect(style.group.titleFont == .title2.bold())
        #expect(style.group.titlePadding == 20)

        #expect(style.screen.contentMaximumHeight == 440)
        #expect(style.screen.contentShade == .black)
        #expect(style.screen.contentShadeOpacity == 0.08)
        #expect(style.screen.background == Color(.systemBackground))
        #expect(style.screen.cornerRadius == 22)
        #expect(style.screen.borderWidth == 1)
        #expect(style.screen.shadow == .init(
            color: .black,
            opacity: 0.12,
            radius: 12,
            offsetY: 5,
        ))
        #expect(style.screen.header == .init(font: .headline, padding: 12))
        #expect(style.screen.placeholder == .init(
            spacing: 12,
            iconFont: .largeTitle,
            titleFont: .headline,
            messageFont: .caption,
            messageMaximumWidth: 220,
            controlSize: .small,
        ))
    }

    @Test func contentAndControlDefaults() {
        #expect(style.screenContent.overviewMaximumSize == CGSize(width: 260, height: 430))
        #expect(style.screenContent.cornerRadius == 18)
        #expect(style.screenControls.spacing == 8)
        #expect(style.screenControls.padding == 12)
        #expect(style.screenControls.maximumHeight == 126)
        #expect(style.screenControls.controlSize == .small)

        #expect(style.controlBar.wideSpacing == 16)
        #expect(style.controlBar.wideViewModeWidth == 220)
        #expect(style.controlBar.wideZoomWidth == 240)
        #expect(style.controlBar.compactSpacing == 12)
        #expect(style.controlBar.compactViewModeWidth == 160)
        #expect(style.controlBar.compactZoomWidth == 180)
        #expect(style.controlBar.focusedSpacing == 16)
        #expect(style.controlBar.focusedControlMinimumWidth == 160)
        #expect(style.controlBar.horizontalPadding == 16)
        #expect(style.controlBar.verticalPadding == 10)
        #expect(style.controlBar.controlSize == .small)
        #expect(style.focused.contentPadding == 24)
    }

    @Test func listRouteAndConnectorDefaults() {
        #expect(style.list.groupSpacing == 40)
        #expect(style.list.contentPadding == 32)
        #expect(style.list.groupTitleFont == .title.bold())

        #expect(style.routeSummary.spacing == 8)
        #expect(style.routeSummary.font == .caption2)
        #expect(style.routeSummary.horizontalPadding == 12)
        #expect(style.routeSummary.bottomPadding == 10)
        #expect(style.routeSummary.height == 34)

        #expect(style.connector.curvature == 0.45)
        #expect(style.connector.minimumControlOffset == 40)
        #expect(style.connector.lineWidth == 3)
        #expect(style.connector.modalDash == [12, 8])
        #expect(style.connector.arrowWidth == 12)
        #expect(style.connector.arrowHalfHeight == 7)
        #expect(style.connector.labelFont == .caption.bold())
        #expect(style.connector.labelOffsetY == 12)
        #expect(style.connector.pushColor == .blue)
        #expect(style.connector.modalColor == .purple)
    }

    @MainActor
    @Test func resolvesThroughBroadwayToTheDefaults() throws {
        let context = BContext(traits: .system)
        let resolved = try context.stylesheets.get(FlyoverStylesheet.self)

        #expect(resolved == .default)
    }

    @MainActor
    @Test func removesDecorativeTransparencyWhenReduced() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.accessibility = BAccessibility(
            isReduceTransparencyEnabled: true,
        )
        let resolved = try context.stylesheets.get(FlyoverStylesheet.self)

        #expect(resolved.group.fillOpacity == 1)
        #expect(resolved.screen.shadow.opacity == 0)
    }
}
