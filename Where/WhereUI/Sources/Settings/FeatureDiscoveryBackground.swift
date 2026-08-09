import SwiftUI

/// A quiet topographic security-print field for feature-marketing screens. Its
/// irregular concentric contours take their visual cue from Where's location
/// cards while owning a renderer and appearance values for this larger canvas.
struct FeatureDiscoveryBackground: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let pattern = stylesheet.featureDiscovery.backgroundPattern
        ZStack {
            Color(.systemGroupedBackground)
            Canvas { context, size in
                drawContours(in: &context, size: size, style: pattern)
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private func drawContours(
        in context: inout GraphicsContext,
        size: CGSize,
        style: WhereStylesheet.FeatureDiscoveryStyle.BackgroundPattern,
    ) {
        let center = CGPoint(
            x: size.width * style.centerXRatio,
            y: size.height * style.centerYRatio,
        )
        let furthestCorner = [
            CGPoint.zero,
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
        .map { hypot(($0.x - center.x) / style.horizontalScale, $0.y - center.y) }
        .max() ?? 0
        let ringCount = Int(ceil(furthestCorner / style.contourSpacing)) + 2
        let segmentCount = 144

        context.drawLayer { layer in
            layer.opacity = style.opacity
            for ring in 1 ... max(1, ringCount) {
                let radius = CGFloat(ring) * style.contourSpacing
                let phase = CGFloat(ring) * style.phaseStep
                var path = Path()
                for segment in 0 ... segmentCount {
                    let angle = CGFloat(segment) * 2 * .pi / CGFloat(segmentCount)
                    let distortion = sin(angle * 3 + phase) * style.primaryDistortion
                        + sin(angle * 7 - phase * 0.7) * style.secondaryDistortion
                    let contourRadius = radius + distortion
                    let point = CGPoint(
                        x: center.x + cos(angle) * contourRadius * style.horizontalScale,
                        y: center.y + sin(angle) * contourRadius,
                    )
                    if segment == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                path.closeSubpath()
                layer.stroke(
                    path,
                    with: .foreground,
                    lineWidth: style.lineWidth,
                )
            }
        }
    }
}

#if DEBUG
    #Preview {
        FeatureDiscoveryBackground()
            .whereBroadwayRoot()
    }
#endif
