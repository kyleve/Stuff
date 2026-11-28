import SFSafeSymbols
import SwiftUI

struct FeatureMarketingHeaderRow: View {
    let title: String
    let tagline: LocalizedStringResource
    let destination: SettingsDestination

    var body: some View {
        FeatureMarketingHeader(
            title: title,
            tagline: String(localized: tagline),
            systemSymbol: destination.systemSymbol,
            tint: destination.iconColor,
        )
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .staggeredReveal(order: 0)
    }
}

#if DEBUG
    #Preview { FeatureMarketingHeaderRow(
        title: SettingsDestination.placesYear.rowTitle,
        tagline: .settingsExplorePlacesTagline,
        destination: .placesYear,
    ).whereBroadwayRoot() }
#endif

private struct FeatureMarketingHeader: View {
    let title: String
    let tagline: String
    let systemSymbol: SFSymbol
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.marketingHeader
        VStack(spacing: style.spacing) {
            FeatureMarketingBadge(systemSymbol: systemSymbol, tint: tint)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(tagline)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: style.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, style.verticalPadding)
    }
}

private struct FeatureMarketingBadge: View {
    let systemSymbol: SFSymbol
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.marketingHeader
        Image(systemSymbol: systemSymbol)
            .font(.system(size: style.symbolPointSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: style.badgeSize, height: style.badgeSize)
            .background(tint.opacity(style.badgeTintOpacity), in: .circle)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        FeatureMarketingHeader(
            title: "Siri, Shortcuts & Spotlight",
            tagline: "Ask, automate, or search for where you’ve been.",
            systemSymbol: .waveform,
            tint: .pink,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
