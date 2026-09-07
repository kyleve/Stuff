import RegionKit
import SFSafeSymbols
import SwiftUI

/// A passport-inspired acknowledgement of the user's current tracked region.
struct RegionWelcomeCard: View {
    let presentation: LocationWelcomeModel.Presentation
    let dismissAction: () -> Void
    let planStayAction: ((Region) -> Void)?

    @State private var regionPath = Path()
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.regionOutlinePathCache) private var regionOutlinePathCache

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
                shape.fill(.clear)
                    .glassEffect(
                        .regular.tint(regionStyle.tint.opacity(welcome.glassTintOpacity)),
                        in: shape,
                    )

                shape.fill(.background)
                    .opacity(welcome.paperOpacity)

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

                    if let artwork = stylesheet.card.regular.regionShape {
                        RegionOutlineArtwork(
                            path: regionPath,
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
        .overlay(alignment: .topTrailing) {
            Button(
                String(localized: .locationWelcomeDismiss),
                systemSymbol: .xmark,
                action: dismissAction,
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .background {
                Circle()
                    .fill(.background)
                    .opacity(welcome.paperOpacity)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.tint(regionStyle.tint.opacity(welcome.close.tintOpacity))
                    .interactive(),
                in: Circle(),
            )
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
        .task(id: presentation.region) {
            guard let regionOutlinePathCache else { return }
            let loaded = await regionOutlinePathCache.path(
                for: presentation.region,
                resolution: .medium,
            )
            guard !Task.isCancelled else { return }
            regionPath = loaded
        }
    }

    private func planStay() {
        planStayAction?(presentation.region)
    }
}

#if DEBUG
    #Preview {
        RegionWelcomeCard(
            presentation: .init(region: .california, greeting: .returnVisit),
            dismissAction: {},
            planStayAction: { _ in },
        )
        .padding(32)
        .whereBroadwayRoot()
    }
#endif
