import RegionKit
import SFSafeSymbols
import SnapshotKit
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

            RegionWelcomeHeading(title: title, regionName: presentation.region.localizedName)

            if planStayAction != nil {
                RegionWelcomePlanButton(tint: regionStyle.tint, planStay: planStay)
            }
        }
        .padding(welcome.padding)
        .frame(maxWidth: welcome.maxWidth)
        .background {
            RegionWelcomeBackground(
                welcome: welcome,
                tint: regionStyle.tint,
                microprint: regionPaths?.microprint,
                watermark: regionPaths?.watermark,
            )
        }
        .matteSurface(welcome.surface, tint: regionStyle.tint, in: shape)
        .overlay(alignment: .topTrailing) {
            RegionWelcomeDismissButton(
                welcome: welcome,
                tint: regionStyle.tint,
                dismissAction: dismissAction,
            )
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

private struct RegionWelcomeHeading: View {
    let title: String
    let regionName: String
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(title)
                .font(.title2.bold())
                .fontDesign(.serif)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: .locationWelcomeMessage(
                regionName,
            )))
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RegionWelcomePlanButton: View {
    let tint: Color
    let planStay: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Button(
            String(localized: .locationForecastEditStay),
            systemSymbol: .calendarBadgeClock,
            action: planStay,
        )
        .buttonStyle(LocationForecastEndorsementButtonStyle(
            tint: tint,
            expands: true,
            controls: stylesheet.locationForecast.controls,
            ink: stylesheet.locationForecast.ink,
        ))
    }
}

#if DEBUG
    import SnapshotKit

    extension RegionWelcomeCard: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let cache = PreviewSupport.snapshotArtworkCache
            return [whereThemeSnapshot(
                name: "Welcome",
                configurations: .componentRepresentative,
                measurementReadiness: .immediate,
                prepareForCapture: {
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
