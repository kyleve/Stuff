import SwiftUI
import ThrowCore

/// A family-specific top-down silhouette designed for small projector marks.
struct AircraftGlyphShape: Shape {
    let family: AircraftVisualFamily

    func path(in rect: CGRect) -> Path {
        switch family {
            case .heavyJet:
                aircraftPath(in: rect, points: [
                    (0.50, 0.00),
                    (0.60, 0.32),
                    (1.00, 0.58),
                    (0.98, 0.73),
                    (0.61, 0.63),
                    (0.59, 0.84),
                    (0.76, 0.96),
                    (0.73, 1.00),
                    (0.50, 0.94),
                    (0.27, 1.00),
                    (0.24, 0.96),
                    (0.41, 0.84),
                    (0.39, 0.63),
                    (0.02, 0.73),
                    (0.00, 0.58),
                    (0.40, 0.32),
                ])
            case .airliner:
                aircraftPath(in: rect, points: [
                    (0.50, 0.00),
                    (0.59, 0.37),
                    (0.94, 0.57),
                    (0.94, 0.69),
                    (0.60, 0.63),
                    (0.58, 0.85),
                    (0.72, 0.97),
                    (0.69, 1.00),
                    (0.50, 0.94),
                    (0.31, 1.00),
                    (0.28, 0.97),
                    (0.42, 0.85),
                    (0.40, 0.63),
                    (0.06, 0.69),
                    (0.06, 0.57),
                    (0.41, 0.37),
                ])
            case .regionalBusinessJet:
                aircraftPath(in: rect, points: [
                    (0.50, 0.00),
                    (0.57, 0.40),
                    (0.86, 0.61),
                    (0.84, 0.70),
                    (0.58, 0.64),
                    (0.57, 0.84),
                    (0.70, 0.95),
                    (0.67, 1.00),
                    (0.50, 0.94),
                    (0.33, 1.00),
                    (0.30, 0.95),
                    (0.43, 0.84),
                    (0.42, 0.64),
                    (0.16, 0.70),
                    (0.14, 0.61),
                    (0.43, 0.40),
                ])
            case .propeller:
                aircraftPath(in: rect, points: [
                    (0.50, 0.00),
                    (0.57, 0.38),
                    (0.96, 0.48),
                    (0.96, 0.61),
                    (0.57, 0.59),
                    (0.57, 0.82),
                    (0.72, 0.91),
                    (0.70, 0.98),
                    (0.50, 0.92),
                    (0.30, 0.98),
                    (0.28, 0.91),
                    (0.43, 0.82),
                    (0.43, 0.59),
                    (0.04, 0.61),
                    (0.04, 0.48),
                    (0.43, 0.38),
                ])
            case .helicopter:
                helicopterPath(in: rect)
            case .unknown:
                aircraftPath(in: rect, points: [
                    (0.50, 0.03),
                    (0.63, 0.45),
                    (0.88, 0.61),
                    (0.61, 0.65),
                    (0.60, 0.88),
                    (0.72, 0.97),
                    (0.50, 0.91),
                    (0.28, 0.97),
                    (0.40, 0.88),
                    (0.39, 0.65),
                    (0.12, 0.61),
                    (0.37, 0.45),
                ])
        }
    }

    private func aircraftPath(in rect: CGRect, points: [(Double, Double)]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: point(first.0, first.1, rect))
        for value in points.dropFirst() {
            path.addLine(to: point(value.0, value.1, rect))
        }
        path.closeSubpath()
        return path
    }

    private func helicopterPath(in rect: CGRect) -> Path {
        var path = Path()
        let rotor = CGRect(
            x: rect.minX,
            y: rect.minY + rect.height * 0.38,
            width: rect.width,
            height: max(1, rect.height * 0.10),
        )
        path.addRoundedRect(
            in: rotor,
            cornerSize: CGSize(width: rotor.height / 2, height: rotor.height / 2),
        )
        path.addEllipse(in: CGRect(
            x: rect.minX + rect.width * 0.32,
            y: rect.minY + rect.height * 0.12,
            width: rect.width * 0.36,
            height: rect.height * 0.48,
        ))
        path.move(to: point(0.45, 0.55, rect))
        path.addLine(to: point(0.55, 0.55, rect))
        path.addLine(to: point(0.57, 0.91, rect))
        path.addLine(to: point(0.75, 0.82, rect))
        path.addLine(to: point(0.78, 0.91, rect))
        path.addLine(to: point(0.55, 1.00, rect))
        path.addLine(to: point(0.45, 1.00, rect))
        path.closeSubpath()
        return path
    }

    private func point(_ x: Double, _ y: Double, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}

/// The small rear portion that can carry a muted carrier color.
struct AircraftAccentShape: Shape {
    let family: AircraftVisualFamily

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch family {
            case .helicopter:
                path.move(to: point(0.45, 0.76, rect))
                path.addLine(to: point(0.57, 0.76, rect))
                path.addLine(to: point(0.57, 0.91, rect))
                path.addLine(to: point(0.75, 0.82, rect))
                path.addLine(to: point(0.78, 0.91, rect))
                path.addLine(to: point(0.55, 1.00, rect))
                path.addLine(to: point(0.45, 1.00, rect))
            case .heavyJet, .airliner, .regionalBusinessJet, .propeller, .unknown:
                path.move(to: point(0.42, 0.77, rect))
                path.addLine(to: point(0.58, 0.77, rect))
                path.addLine(to: point(0.60, 0.88, rect))
                path.addLine(to: point(0.74, 0.97, rect))
                path.addLine(to: point(0.50, 0.93, rect))
                path.addLine(to: point(0.26, 0.97, rect))
                path.addLine(to: point(0.40, 0.88, rect))
        }
        path.closeSubpath()
        return path
    }

    private func point(_ x: Double, _ y: Double, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}
