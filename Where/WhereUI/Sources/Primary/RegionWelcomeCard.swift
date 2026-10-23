import RegionKit
import SFSafeSymbols
import SwiftUI

/// A passport-inspired acknowledgement of the user's current tracked region.
struct RegionWelcomeCard: View {
    let presentation: LocationWelcomeModel.Presentation
    let dismissAction: () -> Void
    let planStayAction: ((Region) -> Void)?

    @State private var artworkModel = RegionArtworkModel<Region, ArtworkPaths>()

    private var regionPaths: ArtworkPaths? {
        artworkModel.artwork(for: presentation.region)
    }

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var welcome: WhereStylesheet.LocationWelcomeStyle {
        stylesheet.locationWelcome
    }

    private var regionStyle: RegionStyle {
        regionStyles.style(for: presentation.region)
    }

    private var title: String {
        switch presentation.greeting {
            case .first:
                String(localized: .locationWelcomeFirstTitle(presentation.region.localizedName))
            case .returnVisit:
                String(localized: .locationWelcomeReturnTitle(presentation.region.localizedName))
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: welcome.cornerRadius)
        VStack(alignment: .leading, spacing: welcome.contentSpacing) {
            HStack {
                Text(regionStyle.emoji)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Spacer()
                PassportSeal(systemSymbol: regionStyle.symbol, tint: regionStyle.tint)
            }

            VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                Text(title)
                    .font(.title2.bold())
                    .fontDesign(.serif)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: .locationWelcomeMessage(
                    presentation.region.localizedName,
                )))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if planStayAction != nil {
                Button(
                    String(localized: .locationForecastEditStay),
                    systemSymbol: .calendarBadgeClock,
                    action: planStay,
                )
                .buttonStyle(LocationForecastEndorsementButtonStyle(
                    tint: regionStyle.tint,
                    expands: true,
                    controls: stylesheet.locationForecast.controls,
                    ink: stylesheet.locationForecast.ink,
                ))
            }
        }
        .padding(welcome.padding)
        .frame(maxWidth: welcome.maxWidth)
        .background {
            ZStack {
                if welcome.surface.usesReflection {
                    shape.fill(.clear)
                        .glassEffect(
                            .regular.tint(regionStyle.tint.opacity(welcome.glassTintOpacity)),
                            in: shape,
                        )

                    shape.fill(.background)
                        .opacity(welcome.paperOpacity)
                }

                ZStack {
                    SecurityPrintRosette(
                        tint: regionStyle.tint,
                        wobble: stylesheet.card.regular.rosette.wobble,
                        lineWidth: stylesheet.card.regular.rosette.lineWidth,
                        primaryRingSpacing: stylesheet.card.regular.rosette.primaryRingSpacing,
                        secondaryRingSpacing: stylesheet.card.regular.rosette.secondaryRingSpacing,
                        primaryOpacity: stylesheet.card.rosetteFill.primary,
                        secondaryOpacity: stylesheet.card.rosetteFill.secondary,
                    )

                    if
                        let regionShape = stylesheet.card.regular.regionShape,
                        let microprint = regionPaths?.microprint,
                        !microprint.isEmpty
                    {
                        RegionOutlineSecurityBorder(
                            paths: [microprint],
                            tint: regionStyle.tint,
                            cornerRadius: welcome.cornerRadius,
                            inset: regionShape.securityBorder.inset,
                            glyphSize: regionShape.securityBorder.glyphSize,
                            spacing: regionShape.securityBorder.spacing,
                            opacity: regionShape.securityBorder.opacity,
                        )
                    }

                    if
                        let artwork = stylesheet.card.regular.regionShape,
                        let watermark = regionPaths?.watermark,
                        !watermark.isEmpty
                    {
                        RegionOutlineArtwork(
                            path: watermark,
                            tint: regionStyle.tint,
                            style: artwork.watermark,
                        )
                    }
                }
                .blendMode(stylesheet.card.securityPrint.backgroundBlendMode)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .matteSurface(welcome.surface, tint: regionStyle.tint, in: shape)
        .overlay(alignment: .topTrailing) {
            Button(action: dismissAction) {
                Label(String(localized: .locationWelcomeDismiss), systemSymbol: .xmark)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .background {
                if welcome.close.surface.usesReflection {
                    Circle()
                        .fill(.background)
                        .opacity(welcome.paperOpacity)
                }
            }
            .buttonStyle(welcome.close.buttonStyle(tint: regionStyle.tint))
            .modifier(RegionWelcomeCloseSurface(style: welcome.close, tint: regionStyle.tint))
            .contentShape(Circle())
            .shadow(
                color: regionStyle.tint.opacity(welcome.close.glow.opacity),
                radius: welcome.close.glow.radius,
                y: welcome.close.glow.offsetY,
            )
            .shadow(
                color: .black.opacity(welcome.close.lift.opacity),
                radius: welcome.close.lift.radius,
                y: welcome.close.lift.offsetY,
            )
            .offset(welcome.close.offset)
        }
        .shadow(
            color: regionStyle.tint.opacity(welcome.glow.opacity),
            radius: welcome.glow.radius,
            y: welcome.glow.offsetY,
        )
        .shadow(
            color: .black.opacity(welcome.lift.opacity),
            radius: welcome.lift.radius,
            y: welcome.lift.offsetY,
        )
        .regionArtworkTask(id: presentation.region, model: artworkModel) { regionOutlinePathCache in
            let region = presentation.region
            async let watermark = regionOutlinePathCache.path(
                for: region,
                resolution: .medium,
            )
            async let microprint = regionOutlinePathCache.path(
                for: region,
                resolution: .micro,
            )
            let (watermarkPath, microprintPath) = await (watermark, microprint)
            return ArtworkPaths(
                watermark: watermarkPath,
                microprint: microprintPath,
            )
        }
    }

    private func planStay() {
        planStayAction?(presentation.region)
    }

    private struct ArtworkPaths {
        let watermark: Path
        let microprint: Path
    }
}

#if DEBUG
    import SnapshotKit

    extension RegionWelcomeCard: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let cache = RegionOutlinePathCache()
            return [whereThemeSnapshot(
                name: "Welcome",
                configurations: .componentDefaults,
                measurementReadiness: .immediate,
                onReadyToSnapshot: {
                    _ = await cache.path(for: .newYork, resolution: .medium)
                    _ = await cache.path(for: .newYork, resolution: .micro)
                },
            ) {
                RegionWelcomeCard(
                    presentation: .init(region: .newYork, greeting: .returnVisit),
                    dismissAction: {},
                    planStayAction: { _ in },
                )
                .padding(24)
                .background(.background)
                .environment(\.regionOutlinePathCache, cache)
            }]
        }
    }

    #Preview {
        RegionWelcomeCard.snapshotPreviews
    }
#endif
