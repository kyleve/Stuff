import RegionKit
import SFSafeSymbols
import SwiftUI

/// A passport-inspired acknowledgement of the user's current tracked region.
struct RegionWelcomeCard: View {
    let presentation: LocationWelcomeModel.Presentation
    let dismissAction: () -> Void

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
        VStack(spacing: welcome.contentSpacing) {
            HStack {
                Text(regionStyle.emoji)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Spacer()
                PassportSeal(systemSymbol: regionStyle.symbol, tint: regionStyle.tint)
            }

            if let artwork = stylesheet.card.regular.regionShape {
                RegionOutlineArtwork(
                    path: regionPath,
                    tint: regionStyle.tint,
                    style: artwork.watermark,
                )
                .frame(maxWidth: .infinity)
                .frame(height: welcome.artworkHeight)
            }

            VStack(spacing: stylesheet.spacing.medium) {
                Text(title)
                    .font(.title2.bold())
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: .locationWelcomeMessage(
                    presentation.region.localizedName,
                )))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(welcome.padding)
        .frame(maxWidth: welcome.maxWidth)
        .background {
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
                shape.fill(.clear)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .glassEffect(
            .regular.tint(regionStyle.tint.opacity(welcome.glassTintOpacity)),
            in: shape,
        )
        .overlay {
            ZStack {
                shape.strokeBorder(
                    regionStyle.tint.opacity(welcome.outlineOpacity),
                    lineWidth: welcome.outlineWidth,
                )
                shape.inset(by: welcome.inset).strokeBorder(
                    regionStyle.tint.opacity(welcome.outlineOpacity),
                    style: StrokeStyle(
                        lineWidth: welcome.outlineWidth,
                        dash: [welcome.insetDashLength, welcome.insetDashSpacing],
                    ),
                )
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button(
                String(localized: .locationWelcomeDismiss),
                systemSymbol: .xmark,
                action: dismissAction,
            )
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
            .contentShape(Circle())
            .offset(welcome.closeOffset)
        }
        .shadow(
            color: regionStyle.tint.opacity(welcome.shadowOpacity),
            radius: welcome.shadowRadius,
            y: welcome.shadowOffsetY,
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
}

#if DEBUG
    #Preview {
        RegionWelcomeCard(
            presentation: .init(region: .california, greeting: .returnVisit),
            dismissAction: {},
        )
        .padding(32)
        .whereBroadwayRoot()
    }
#endif
