import SFSafeSymbols
import SwiftUI

/// A gallery explanation with an optional production visual beneath it.
struct FeatureGuidePanel<Content: View>: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbol: SFSymbol
    @ViewBuilder let content: Content
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureMarketingPanel {
            VStack(
                alignment: .leading,
                spacing: stylesheet.featureDiscovery.marketingPanel.contentSpacing,
            ) {
                Label(String(localized: title), systemSymbol: symbol)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
        }
    }
}

#if DEBUG
    #Preview {
        FeatureGuidePanel(
            title: .settingsExplorePlacesLocationsTitle,
            detail: .settingsExplorePlacesLocationsDetail,
            symbol: .mapFill,
        ) {}
            .whereBroadwayRoot()
    }
#endif
