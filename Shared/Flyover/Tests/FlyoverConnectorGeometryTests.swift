import CoreGraphics
@testable import Flyover
import Testing

struct FlyoverConnectorGeometryTests {
    @Test func forwardRouteUsesTrailingToLeadingEdgesAndPointsRight() {
        let geometry = FlyoverConnectorGeometry(
            source: CGRect(x: 0, y: 0, width: 100, height: 200),
            destination: CGRect(x: 300, y: 100, width: 100, height: 200),
            style: style,
        )

        #expect(geometry.start == CGPoint(x: 100, y: 100))
        #expect(geometry.end == CGPoint(x: 300, y: 200))
        #expect(geometry.firstControl == CGPoint(x: 190, y: 100))
        #expect(geometry.secondControl == CGPoint(x: 210, y: 200))
        #expect(geometry.firstArrowPoint == CGPoint(x: 280, y: 190))
        #expect(geometry.secondArrowPoint == CGPoint(x: 280, y: 210))
    }

    @Test func backwardRouteUsesLeadingToTrailingEdgesAndPointsLeft() {
        let geometry = FlyoverConnectorGeometry(
            source: CGRect(x: 300, y: 100, width: 100, height: 200),
            destination: CGRect(x: 0, y: 0, width: 100, height: 200),
            style: style,
        )

        #expect(geometry.start == CGPoint(x: 300, y: 200))
        #expect(geometry.end == CGPoint(x: 100, y: 100))
        #expect(geometry.firstControl == CGPoint(x: 210, y: 200))
        #expect(geometry.secondControl == CGPoint(x: 190, y: 100))
        #expect(geometry.firstArrowPoint == CGPoint(x: 120, y: 90))
        #expect(geometry.secondArrowPoint == CGPoint(x: 120, y: 110))
    }

    private var style: FlyoverStylesheet.ConnectorStyle {
        var style = FlyoverStylesheet.default.connector
        style.curvature = 0.45
        style.minimumControlOffset = 40
        style.arrowWidth = 20
        style.arrowHalfHeight = 10
        return style
    }
}
