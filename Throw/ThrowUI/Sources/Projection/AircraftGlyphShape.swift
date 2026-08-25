import SwiftUI

/// A small top-down aircraft silhouette designed to remain legible at projector scale.
struct AircraftGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + width * x,
                y: rect.minY + height * y,
            )
        }

        var path = Path()
        path.move(to: point(0.5, 0))
        path.addLine(to: point(0.62, 0.38))
        path.addLine(to: point(1, 0.55))
        path.addLine(to: point(1, 0.7))
        path.addLine(to: point(0.61, 0.62))
        path.addLine(to: point(0.58, 0.86))
        path.addLine(to: point(0.75, 1))
        path.addLine(to: point(0.25, 1))
        path.addLine(to: point(0.42, 0.86))
        path.addLine(to: point(0.39, 0.62))
        path.addLine(to: point(0, 0.7))
        path.addLine(to: point(0, 0.55))
        path.addLine(to: point(0.38, 0.38))
        path.closeSubpath()
        return path
    }
}
