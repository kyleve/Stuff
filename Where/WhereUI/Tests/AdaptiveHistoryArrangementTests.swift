import CoreGraphics
import Testing
@testable import WhereUI

struct AdaptiveHistoryArrangementTests {
    private let style = AdaptiveHistoryTestSupport.multiplePaneStyle

    @Test func anActiveHorizontalDivisionSeparatesHistoryAndControls() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        geometry.regions = [AdaptiveHistoryTestSupport.horizontalDivision]
        let arrangement = AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style)
        guard case let .tabletop(panes) = arrangement else {
            Issue.record("A usable horizontal division must choose tabletop.")
            return
        }
        #expect(panes.history == CGRect(x: 0, y: 82, width: 669, height: 373.5))
        #expect(panes.controls == CGRect(x: 0, y: 495.5, width: 669, height: 421.5))
        #expect(panes.controls.minY - panes.history.maxY == 40)
    }

    @Test func aFlatDisplayIgnoresItsInactiveDivision() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        var division = AdaptiveHistoryTestSupport.horizontalDivision
        division.isActive = false
        geometry.regions = [division]
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style) == .columns)
    }

    @Test func verticalDivisionsRetainBrowseAndDetail() {
        let geometry = AdaptiveHistoryGeometry(
            bounds: CGRect(x: 0, y: 0, width: 951, height: 669),
            insets: .init(top: 0, left: 0, bottom: 34, right: 84),
            regions: [.init(
                kind: .division,
                frame: CGRect(x: 455.5, y: 0, width: 40, height: 669),
                isActive: true,
            )],
            layoutDirection: .leftToRight,
        )
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style) == .columns)
    }

    @Test func insufficientSpaceAndSinglePanePolicyCollapse() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        geometry.bounds.size.width = style.minimumControlsWidth + style.minimumHistoryWidth - 1
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style) == .compact)
        geometry = AdaptiveHistoryTestSupport.portrait
        geometry.regions = [AdaptiveHistoryTestSupport.horizontalDivision]
        var single = style
        single.panes = .single
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: single) == .compact)
        geometry.regions[0].frame.origin.y = 200
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style) == .compact)
    }

    @Test func sideBarsParticipateInTheFitDecision() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        geometry.insets.left = 40
        geometry.insets.right = 84
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style) == .compact)
    }

    @Test func rightToLeftPlacesTheHistoryWidthOnTheOppositeSide() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        geometry.bounds.size.width = 780
        geometry.regions = [.init(
            kind: .division,
            frame: CGRect(x: 300, y: 0, width: 40, height: 951),
            isActive: true,
        )]
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style) == .columns)
        geometry.layoutDirection = .rightToLeft
        #expect(AdaptiveHistoryArrangement.resolve(geometry: geometry, style: style) == .compact)
    }

    @Test(arguments: [true, false])
    func tabletopAvoidsOnlyActiveOcclusions(isActive: Bool) {
        var geometry = AdaptiveHistoryTestSupport.portrait
        let camera = CGRect(x: 21, y: 210, width: 37, height: 58)
        geometry.regions = [
            AdaptiveHistoryTestSupport.horizontalDivision,
            .init(kind: .occlusion, frame: camera, isActive: isActive),
        ]
        guard case let .tabletop(panes) = AdaptiveHistoryArrangement.resolve(
            geometry: geometry,
            style: style,
        ) else {
            Issue.record("The camera leaves sufficient space for tabletop.")
            return
        }
        #expect(panes.history.intersection(camera).isEmpty == isActive)
        #expect(panes.controls.maxY == geometry.contentBounds.maxY)
    }
}
