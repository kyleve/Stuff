import SwiftUI

/// Decorative glass and quiet security print beneath the Locations estimate.
struct LocationForecastSummarySurface: View {
    let artwork: [LocationForecastArtworkLoader.Item]

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.whereComponentStylesheet) private var components

    var body: some View {
        let style = stylesheet.locationForecast.summary
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)

        ZStack {
            // The surface keeps its host's bounds when every optional mark is removed.
            Color.clear
            if let background = components[.summary].background { shape.fill(background) }
            if components[.summary].nativeArtwork.contains(.rosette) {
                SecurityPrintRosette(
                    tint: style.ink,
                    wobble: style.rosette.wobble,
                    lineWidth: style.rosette.lineWidth,
                    primaryRingSpacing: style.rosette.primaryRingSpacing,
                    secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                    primaryOpacity: style.rosetteOpacity,
                    secondaryOpacity: style.rosetteOpacity,
                )
            }
            if components[.summary].nativeArtwork.contains(.microprint) {
                RegionOutlineSecurityBorder(
                    paths: artwork.map(\.microprint),
                    tint: style.ink,
                    cornerRadius: style.cornerRadius,
                    inset: style.border.inset,
                    glyphSize: style.border.glyphSize,
                    spacing: style.border.spacing,
                    opacity: style.border.opacity,
                )
            }
            if components[.summary].nativeArtwork
                .contains(.watermark) { LocationForecastSilhouettes(artwork: artwork) }
            WhereComponentArtwork(role: .summary, plane: .interior, shape: shape)
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
        .overlay {
            if style.treatment.usesReflection {
                shape.inset(by: -style.outlineWidth).strokeBorder(
                    style.outlineColor,
                    lineWidth: style.outlineWidth,
                )
            }
        }
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
        LocationForecastSummarySurface(artwork: [])
            .frame(height: 104)
            .padding()
            .whereBroadwayRoot()
    }
#endif
