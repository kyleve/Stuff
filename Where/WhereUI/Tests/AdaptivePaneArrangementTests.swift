import CoreGraphics
import Testing
@testable import WhereUI

struct AdaptivePaneArrangementTests {
    private let style = AdaptivePaneTestSupport.multiplePaneStyle

    @Test func anActiveHorizontalDivisionSeparatesDetailAndControls() {
        var geometry = AdaptivePaneTestSupport.portrait
        geometry.regions = [AdaptivePaneTestSupport.horizontalDivision]
        let arrangement = AdaptivePaneArrangement.resolve(geometry: geometry, style: style)
        guard case let .tabletop(panes) = arrangement else {
            Issue.record("A usable horizontal division must choose tabletop.")
            return
        }
        #expect(panes.detail == CGRect(x: 0, y: 82, width: 669, height: 373.5))
        #expect(panes.controls == CGRect(x: 0, y: 495.5, width: 669, height: 421.5))
        #expect(panes.controls.minY - panes.detail.maxY == 40)
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
        geometry.regions[0].frame.origin.y = 200
        #expect(AdaptivePaneArrangement.resolve(geometry: geometry, style: style) == .compact)
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

    @Test(arguments: [true, false])
    func tabletopAvoidsOnlyActiveOcclusions(isActive: Bool) {
        var geometry = AdaptivePaneTestSupport.portrait
        let camera = CGRect(x: 21, y: 210, width: 37, height: 58)
        geometry.regions = [
            AdaptivePaneTestSupport.horizontalDivision,
            .init(kind: .occlusion, frame: camera, isActive: isActive),
        ]
        guard case let .tabletop(panes) = AdaptivePaneArrangement.resolve(
            geometry: geometry,
            style: style,
        ) else {
            Issue.record("The camera leaves sufficient space for tabletop.")
            return
        }
        #expect(panes.detail.intersection(camera).isEmpty == isActive)
        #expect(panes.controls.maxY == geometry.contentBounds.maxY)
    }
}
