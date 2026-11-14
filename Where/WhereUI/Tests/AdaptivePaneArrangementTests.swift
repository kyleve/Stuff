import CoreGraphics
import Testing
@testable import WhereUI

struct AdaptivePaneArrangementTests {
    private let style = AdaptivePaneTestSupport.multiplePaneStyle

    @Test func portraitTabletopRetainsBrowseAndDetailColumns() {
        var geometry = AdaptivePaneTestSupport.portrait
        geometry.regions = [AdaptivePaneTestSupport.horizontalDivision]
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .columns)
        geometry.layoutDirection = .rightToLeft
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .columns)
        geometry.bounds.size.width = style.minimumControlsWidth + style.minimumDetailWidth - 1
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .compact)
    }

    @Test func landscapeHorizontalFoldsAlsoRetainColumns() {
        #expect(AdaptivePaneArrangement.resolve(
            geometry: AdaptivePaneTestSupport.landscapeTabletop,
            style: style,
        ) == .columns)
    }

    @Test func aFlatDisplayIgnoresItsInactiveDivision() {
        var geometry = AdaptivePaneTestSupport.portrait
        var division = AdaptivePaneTestSupport.horizontalDivision
        division.isActive = false
        geometry.regions = [division]
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .columns)
    }

    @Test func verticalDivisionsRetainBrowseAndDetail() {
        let geometry = AdaptivePaneGeometry(
            bounds: CGRect(x: 0, y: 0, width: 951, height: 669),
            insets: .init(top: 0, left: 0, bottom: 34, right: 84),
            regions: [.init(
                kind: .division,
                frame: CGRect(x: 455.5, y: 0, width: 40, height: 669),
                isActive: true,
            )],
            layoutDirection: .leftToRight,
        )
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .columns)
    }

    @Test func insufficientSpaceAndSinglePanePolicyCollapse() {
        var geometry = AdaptivePaneTestSupport.portrait
        geometry.bounds.size.width = style.minimumControlsWidth + style.minimumDetailWidth - 1
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .compact)
        geometry = AdaptivePaneTestSupport.portrait
        geometry.regions = [AdaptivePaneTestSupport.horizontalDivision]
        var single = style
        single.panes = .single
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: single) == .compact)
    }

    @Test func sideBarsParticipateInTheFitDecision() {
        var geometry = AdaptivePaneTestSupport.portrait
        geometry.insets.left = 40
        geometry.insets.right = 84
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .compact)
    }

    @Test func rightToLeftPlacesTheDetailWidthOnTheOppositeSide() {
        var geometry = AdaptivePaneTestSupport.portrait
        geometry.bounds.size.width = 780
        geometry.regions = [.init(
            kind: .division,
            frame: CGRect(x: 300, y: 0, width: 40, height: 951),
            isActive: true,
        )]
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .columns)
        geometry.layoutDirection = .rightToLeft
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .compact)
    }
}
