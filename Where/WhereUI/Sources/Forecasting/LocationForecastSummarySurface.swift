import SwiftUI

/// Decorative glass and quiet security print beneath the Locations estimate.
struct LocationForecastSummarySurface: View {
    let paths: [Path]

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast.summary
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)

        ZStack {
            SecurityPrintRosette(
                tint: style.ink,
                wobble: style.rosette.wobble,
                lineWidth: style.rosette.lineWidth,
                primaryRingSpacing: style.rosette.primaryRingSpacing,
                secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                primaryOpacity: style.rosetteOpacity,
                secondaryOpacity: style.rosetteOpacity,
            )
            RegionOutlineSecurityBorder(
                paths: paths,
                tint: style.ink,
                cornerRadius: style.cornerRadius,
                inset: style.border.inset,
                glyphSize: style.border.glyphSize,
                spacing: style.border.spacing,
                opacity: style.border.opacity,
            )
        }
        .background {
            if style.treatment.usesReflection {
                if style.usesOpaquePaper {
                    shape.fill(style.paper)
                } else {
                    shape.fill(.clear)
                        .glassEffect(
                            .regular.tint(style.ink.opacity(style.glassTintOpacity)),
                            in: shape,
                        )
                }
            }
        }
        .clipShape(shape)
        .matteSurface(style.treatment, tint: style.ink, in: shape)
        .shadow(
            color: .black.opacity(style.shadowOpacity),
            radius: style.shadowRadius,
            y: style.shadowOffsetY,
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        LocationForecastSummarySurface(paths: [])
            .frame(height: 104)
            .padding()
            .whereBroadwayRoot()
    }
#endif
