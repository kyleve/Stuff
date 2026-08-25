import SwiftUI
import ThrowCore

/// A family-specific top-down silhouette designed for small projector marks.
struct AircraftGlyphShape: Shape {
    let family: AircraftVisualFamily

    func path(in rect: CGRect) -> Path {
        switch family {
            case .heavyJet: heavyJetPath(in: rect)
            case .airliner: airlinerPath(in: rect)
            case .regionalBusinessJet: regionalJetPath(in: rect)
            case .propeller: propellerPath(in: rect)
            case .helicopter: helicopterPath(in: rect)
            case .unknown: unknownPath(in: rect)
        }
    }

    private func heavyJetPath(in rect: CGRect) -> Path {
        var path = Path()
        addFuselage(to: &path, in: rect, x: 0.39, width: 0.22, bottom: 0.96)
        addPolygon(to: &path, in: rect, points: [
            (0.41, 0.32),
            (0.03, 0.50),
            (0.03, 0.67),
            (0.42, 0.60),
            (0.58, 0.60),
            (0.97, 0.67),
            (0.97, 0.50),
            (0.59, 0.32),
        ])
        addPolygon(to: &path, in: rect, points: [
            (0.40, 0.77),
            (0.20, 0.88),
            (0.20, 0.96),
            (0.43, 0.91),
            (0.57, 0.91),
            (0.80, 0.96),
            (0.80, 0.88),
            (0.60, 0.77),
        ])
        return path
    }

    private func airlinerPath(in rect: CGRect) -> Path {
        var path = Path()
        addFuselage(to: &path, in: rect, x: 0.43, width: 0.14, bottom: 0.98)
        addPolygon(to: &path, in: rect, points: [
            (0.43, 0.36),
            (0.06, 0.53),
            (0.06, 0.63),
            (0.43, 0.58),
            (0.57, 0.58),
            (0.94, 0.63),
            (0.94, 0.53),
            (0.57, 0.36),
        ])
        addPolygon(to: &path, in: rect, points: [
            (0.43, 0.79),
            (0.27, 0.89),
            (0.27, 0.95),
            (0.45, 0.91),
            (0.55, 0.91),
            (0.73, 0.95),
            (0.73, 0.89),
            (0.57, 0.79),
        ])
        return path
    }

    private func regionalJetPath(in rect: CGRect) -> Path {
        var path = Path()
        addFuselage(to: &path, in: rect, x: 0.42, width: 0.16, bottom: 0.96)
        addPolygon(to: &path, in: rect, points: [
            (0.42, 0.40),
            (0.15, 0.54),
            (0.15, 0.64),
            (0.42, 0.59),
            (0.58, 0.59),
            (0.85, 0.64),
            (0.85, 0.54),
            (0.58, 0.40),
        ])
        addRoundedBar(to: &path, in: rect, x: 0.24, y: 0.84, width: 0.52, height: 0.10)
        return path
    }

    private func propellerPath(in rect: CGRect) -> Path {
        var path = Path()
        addFuselage(to: &path, in: rect, x: 0.42, width: 0.16, bottom: 0.96)
        addRoundedBar(to: &path, in: rect, x: 0.24, y: 0.02, width: 0.52, height: 0.10)
        addPolygon(to: &path, in: rect, points: [
            (0.42, 0.38),
            (0.03, 0.42),
            (0.03, 0.57),
            (0.42, 0.56),
            (0.58, 0.56),
            (0.97, 0.57),
            (0.97, 0.42),
            (0.58, 0.38),
        ])
        addPolygon(to: &path, in: rect, points: [
            (0.42, 0.78),
            (0.25, 0.83),
            (0.25, 0.92),
            (0.44, 0.89),
            (0.56, 0.89),
            (0.75, 0.92),
            (0.75, 0.83),
            (0.58, 0.78),
        ])
        return path
    }

    private func helicopterPath(in rect: CGRect) -> Path {
        var path = Path()
        addRoundedBar(to: &path, in: rect, x: 0.00, y: 0.39, width: 1.00, height: 0.11)
        addRoundedBar(to: &path, in: rect, x: 0.445, y: 0.02, width: 0.11, height: 0.74)
        path.addEllipse(in: CGRect(
            x: rect.minX + rect.width * 0.31,
            y: rect.minY + rect.height * 0.20,
            width: rect.width * 0.38,
            height: rect.height * 0.45,
        ))
        addPolygon(to: &path, in: rect, points: [
            (0.45, 0.57),
            (0.55, 0.57),
            (0.57, 0.95),
            (0.43, 0.95),
        ])
        addRoundedBar(to: &path, in: rect, x: 0.29, y: 0.87, width: 0.42, height: 0.09)
        return path
    }

    private func unknownPath(in rect: CGRect) -> Path {
        var path = Path()
        addFuselage(to: &path, in: rect, x: 0.42, width: 0.16, bottom: 0.96)
        addPolygon(to: &path, in: rect, points: [
            (0.42, 0.40),
            (0.12, 0.49),
            (0.12, 0.61),
            (0.42, 0.57),
            (0.58, 0.57),
            (0.88, 0.61),
            (0.88, 0.49),
            (0.58, 0.40),
        ])
        addRoundedBar(to: &path, in: rect, x: 0.30, y: 0.82, width: 0.40, height: 0.09)
        return path
    }

    private func addFuselage(
        to path: inout Path,
        in rect: CGRect,
        x: Double,
        width: Double,
        bottom: Double,
    ) {
        let fuselage = CGRect(
            x: rect.minX + rect.width * x,
            y: rect.minY,
            width: rect.width * width,
            height: rect.height * bottom,
        )
        path.addRoundedRect(
            in: fuselage,
            cornerSize: CGSize(width: fuselage.width / 2, height: fuselage.width / 2),
        )
    }

    private func addRoundedBar(
        to path: inout Path,
        in rect: CGRect,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) {
        let bar = CGRect(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y,
            width: rect.width * width,
            height: rect.height * height,
        )
        path.addRoundedRect(
            in: bar,
            cornerSize: CGSize(width: bar.height / 2, height: bar.height / 2),
        )
    }

    private func addPolygon(
        to path: inout Path,
        in rect: CGRect,
        points: [(Double, Double)],
    ) {
        guard let first = points.first else { return }
        path.move(to: point(first.0, first.1, rect))
        for value in points.dropFirst() {
            path.addLine(to: point(value.0, value.1, rect))
        }
        path.closeSubpath()
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
            case .heavyJet:
                addTail(to: &path, in: rect, width: 0.58, top: 0.77)
            case .airliner:
                addTail(to: &path, in: rect, width: 0.42, top: 0.79)
            case .regionalBusinessJet:
                addTail(to: &path, in: rect, width: 0.52, top: 0.82)
            case .propeller:
                addTail(to: &path, in: rect, width: 0.50, top: 0.78)
            case .helicopter:
                let tail = CGRect(
                    x: rect.minX + rect.width * 0.43,
                    y: rect.minY + rect.height * 0.70,
                    width: rect.width * 0.14,
                    height: rect.height * 0.26,
                )
                path.addRoundedRect(
                    in: tail,
                    cornerSize: CGSize(width: tail.width / 2, height: tail.width / 2),
                )
                addRoundedBar(to: &path, in: rect, x: 0.29, y: 0.87, width: 0.42, height: 0.09)
            case .unknown:
                addTail(to: &path, in: rect, width: 0.40, top: 0.82)
        }
        return path
    }

    private func addTail(
        to path: inout Path,
        in rect: CGRect,
        width: Double,
        top: Double,
    ) {
        let bar = CGRect(
            x: rect.minX + rect.width * ((1 - width) / 2),
            y: rect.minY + rect.height * top,
            width: rect.width * width,
            height: rect.height * 0.11,
        )
        path.addRoundedRect(
            in: bar,
            cornerSize: CGSize(width: bar.height / 2, height: bar.height / 2),
        )
        let fuselage = CGRect(
            x: rect.minX + rect.width * 0.42,
            y: rect.minY + rect.height * top,
            width: rect.width * 0.16,
            height: rect.height * (0.98 - top),
        )
        path.addRoundedRect(
            in: fuselage,
            cornerSize: CGSize(width: fuselage.width / 2, height: fuselage.width / 2),
        )
    }

    private func addRoundedBar(
        to path: inout Path,
        in rect: CGRect,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) {
        let bar = CGRect(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y,
            width: rect.width * width,
            height: rect.height * height,
        )
        path.addRoundedRect(
            in: bar,
            cornerSize: CGSize(width: bar.height / 2, height: bar.height / 2),
        )
    }
}
