import Foundation
import SwiftUI
import ThrowCore

public struct CalibrationPatternView: View {
    private let screenTopBearing: Double
    private let rotation: ScreenRotation
    private let flipHorizontal: Bool
    private let flipVertical: Bool
    private let safeInsetPercent: Double

    @Environment(\.throwStylesheet) private var stylesheet

    public init(
        screenTopBearing: Double = 0,
        rotation: ScreenRotation = .degrees0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        safeInsetPercent: Double = 5,
    ) {
        self.screenTopBearing = screenTopBearing
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.safeInsetPercent = safeInsetPercent
    }

    public var body: some View {
        Canvas { context, size in
            let insetFraction = min(max(safeInsetPercent / 100, 0), 0.2)
            let side = min(size.width, size.height) * (1 - insetFraction * 2)
            let rect = CGRect(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2,
                width: side,
                height: side,
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(stylesheet.calibration.line),
                lineWidth: stylesheet.calibration.boundaryLineWidth,
            )

            for fraction in [0.25, 0.5, 0.75] {
                let horizontal = Path { path in
                    let y = rect.minY + rect.height * fraction
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                let vertical = Path { path in
                    let x = rect.minX + rect.width * fraction
                    path.move(to: CGPoint(x: x, y: rect.minY))
                    path.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
                context.stroke(
                    horizontal,
                    with: .color(stylesheet.calibration.secondaryLine),
                    lineWidth: 1,
                )
                context.stroke(
                    vertical,
                    with: .color(stylesheet.calibration.secondaryLine),
                    lineWidth: 1,
                )
            }

            draw(.calibrationNorth, at: cardinalPoint(0, in: rect), in: &context)
            draw(.calibrationEast, at: cardinalPoint(90, in: rect), in: &context)
            draw(.calibrationSouth, at: cardinalPoint(180, in: rect), in: &context)
            draw(.calibrationWest, at: cardinalPoint(270, in: rect), in: &context)
            context.fill(
                Path(ellipseIn: CGRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)),
                with: .color(stylesheet.calibration.line),
            )
        }
        .rotationEffect(.degrees(Double(rotation.rawValue)))
        .scaleEffect(
            x: flipHorizontal ? -1 : 1,
            y: flipVertical ? -1 : 1,
        )
        .background(.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.calibrationPatternAccessibility))
    }

    private func cardinalPoint(_ bearing: Double, in rect: CGRect) -> CGPoint {
        let angle = (bearing - screenTopBearing - 90) * .pi / 180
        let radius = max(rect.width / 2 - 18, 0)
        return CGPoint(
            x: rect.midX + cos(angle) * radius,
            y: rect.midY + sin(angle) * radius,
        )
    }

    private func draw(
        _ value: LocalizedStringResource,
        at point: CGPoint,
        in context: inout GraphicsContext,
    ) {
        context.draw(
            Text(value).font(.headline).foregroundStyle(stylesheet.calibration.line),
            at: point,
        )
    }
}

#if DEBUG
    #Preview {
        CalibrationPatternView()
            .frame(width: 640, height: 360)
            .throwBroadwayRoot()
    }
#endif
