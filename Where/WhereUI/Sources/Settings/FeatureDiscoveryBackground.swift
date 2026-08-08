import SwiftUI

/// A quiet, oversized petal print for feature-marketing screens. It takes its
/// visual cue from Where's security-print cards without sharing their renderer
/// or component-specific appearance values.
struct FeatureDiscoveryBackground: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let pattern = stylesheet.featureDiscovery.backgroundPattern
        ZStack {
            Color(.systemGroupedBackground)
            Canvas { context, size in
                let columns = Int(ceil(size.width / pattern.motifSpacing)) + 2
                let rows = Int(ceil(size.height / pattern.motifSpacing)) + 2
                for row in -1 ..< rows {
                    for column in -1 ..< columns {
                        let offset = row.isMultiple(of: 2) ? 0 : pattern.motifSpacing / 2
                        let center = CGPoint(
                            x: CGFloat(column) * pattern.motifSpacing + offset,
                            y: CGFloat(row) * pattern.motifSpacing,
                        )
                        drawMotif(
                            in: &context,
                            center: center,
                            radius: pattern.motifRadius,
                            petalCount: pattern.petalCount,
                            petalWidthRatio: pattern.petalWidthRatio,
                            lineWidth: pattern.lineWidth,
                            opacity: pattern.primaryOpacity,
                        )
                        drawMotif(
                            in: &context,
                            center: center,
                            radius: pattern.motifRadius * 0.62,
                            petalCount: pattern.petalCount,
                            petalWidthRatio: pattern.petalWidthRatio,
                            lineWidth: pattern.lineWidth,
                            opacity: pattern.secondaryOpacity,
                            rotation: .pi / Double(pattern.petalCount),
                        )
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private func drawMotif(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        petalCount: Int,
        petalWidthRatio: CGFloat,
        lineWidth: CGFloat,
        opacity: Double,
        rotation: Double = 0,
    ) {
        for petal in 0 ..< petalCount {
            context.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .radians(
                    Double(petal) * 2 * .pi / Double(petalCount) + rotation,
                ))
                layer.opacity = opacity
                let rect = CGRect(
                    x: -radius * petalWidthRatio / 2,
                    y: -radius,
                    width: radius * petalWidthRatio,
                    height: radius * 2,
                )
                layer.stroke(
                    Path(ellipseIn: rect),
                    with: .foreground,
                    lineWidth: lineWidth,
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
