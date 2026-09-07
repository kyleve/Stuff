import CoreGraphics

/// Direction-aware path geometry connecting two Flyover screen frames.
struct FlyoverConnectorGeometry: Equatable {
    let start: CGPoint
    let end: CGPoint
    let firstControl: CGPoint
    let secondControl: CGPoint
    let firstArrowPoint: CGPoint
    let secondArrowPoint: CGPoint

    init(
        source: CGRect,
        destination: CGRect,
        style: FlyoverStylesheet.ConnectorStyle,
    ) {
        let direction: CGFloat = destination.midX >= source.midX ? 1 : -1
        start = CGPoint(
            x: direction > 0 ? source.maxX : source.minX,
            y: source.midY,
        )
        end = CGPoint(
            x: direction > 0 ? destination.minX : destination.maxX,
            y: destination.midY,
        )
        let controlOffset = max(
            abs(end.x - start.x) * style.curvature,
            style.minimumControlOffset,
        )
        firstControl = CGPoint(
            x: start.x + direction * controlOffset,
            y: start.y,
        )
        secondControl = CGPoint(
            x: end.x - direction * controlOffset,
            y: end.y,
        )
        firstArrowPoint = CGPoint(
            x: end.x - direction * style.arrowWidth,
            y: end.y - style.arrowHalfHeight,
        )
        secondArrowPoint = CGPoint(
            x: end.x - direction * style.arrowWidth,
            y: end.y + style.arrowHalfHeight,
        )
    }

    var midpoint: CGPoint {
        CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2,
        )
    }
}
