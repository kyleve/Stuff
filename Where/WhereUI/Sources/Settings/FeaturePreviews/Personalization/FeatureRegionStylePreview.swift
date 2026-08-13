import RegionKit
import SFSafeSymbols
import SwiftUI

/// Shows one region's resolved user appearance across the surfaces that share it.
struct FeatureRegionStylePreview: View {
    let region: Region
    let style: RegionStyle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                Label {
                    VStack(alignment: .leading) {
                        Text(String(localized: .settingsExplorePersonalizationRegionsTitle))
                            .font(.headline)
                        Text(region.localizedName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemSymbol: style.symbol)
                        .foregroundStyle(style.tint)
                }

                previewLayout {
                    surface(
                        String(localized: .settingsExplorePersonalizationCards),
                        systemSymbol: style.symbol,
                    )
                    surface(
                        String(localized: .settingsExplorePersonalizationCalendar),
                        systemSymbol: .calendar,
                    )
                    surface(
                        String(localized: .settingsExplorePersonalizationWidgets),
                        systemSymbol: .widgetSmall,
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var previewLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: stylesheet.spacing.small))
        } else {
            AnyLayout(HStackLayout(spacing: stylesheet.spacing.small))
        }
    }

    private func surface(_ title: String, systemSymbol: SFSymbol) -> some View {
        VStack(spacing: stylesheet.spacing.small) {
            Image(systemSymbol: systemSymbol)
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(style.tint.gradient)
                .frame(height: 58)
                .accessibilityHidden(true)

            HStack(spacing: stylesheet.spacing.small) {
                Text(style.emoji)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        FeatureRegionStylePreview(
            region: .california,
            style: RegionStyle(RegionAppearanceCatalog.defaultAppearance(for: .california)),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
