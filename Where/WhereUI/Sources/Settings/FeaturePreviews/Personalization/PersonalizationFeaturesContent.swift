import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
struct PersonalizationFeaturesContent: View {
    let report: YearReportModel
    let iconModel: AppIconModel
    let showRegions: () -> Void
    let showAppIcons: () -> Void

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.isInDemoMode) private var isInDemoMode
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        Form {
            FeatureMarketingHeader(
                title: String(localized: .settingsExplorePersonalizationTitle),
                tagline: String(localized: .settingsExplorePersonalizationTagline),
                systemSymbol: SettingsDestination.personalization.systemSymbol,
                tint: SettingsDestination.personalization.iconColor,
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .staggeredReveal(order: 0)

            Section {
                FeatureRegionStylePreview(region: featuredRegion, style: featuredStyle)
                    .featureMarketingRow(order: 1)
                    .settingsRow(
                        PersonalizationFeaturesView.Item.regions,
                        restingBackground: .clear,
                    )

                FeatureMarketingPanel {
                    Button(action: showRegions) {
                        actionLabel(
                            String(localized: .settingsExplorePersonalizationOpenRegions),
                            systemSymbol: .paintpalette,
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .featureMarketingRow(order: 2)
            }

            Section {
                FeatureAppIconPreview(model: iconModel)
                    .featureMarketingRow(order: 3)
                    .settingsRow(
                        PersonalizationFeaturesView.Item.appIcon,
                        restingBackground: .clear,
                    )

                if !isInDemoMode {
                    FeatureMarketingPanel {
                        Button(action: showAppIcons) {
                            actionLabel(
                                String(localized: .settingsExplorePersonalizationOpenIcon),
                                systemSymbol: .appBadge,
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .featureMarketingRow(order: 4)
                }
            }
            Section {
                FeatureGuidePanel(
                    title: .settingsExplorePersonalizationAppearanceTitle,
                    detail: .settingsExplorePersonalizationAppearanceDetail,
                    symbol: .paintbrushFill,
                ) {}
                    .featureMarketingRow(order: 5)
                    .settingsRow(
                        PersonalizationFeaturesView.Item.appearance,
                        restingBackground: .clear,
                    )
                FeatureSettingsLink(destination: .appearance).featureMarketingRow(order: 6)
            } footer: {
                VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                    Text(String(localized: .settingsExplorePersonalizationFooter))
                    FeatureDiscoveryDataFooter()
                }
                .staggeredReveal(order: 7)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }

    private var featuredRegion: Region {
        report.ranking.primary.first?.region ?? .california
    }

    private var featuredStyle: RegionStyle {
        regionStyles.style(for: featuredRegion)
    }

    private func actionLabel(_ title: String, systemSymbol: SFSymbol) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemSymbol: systemSymbol)
                .foregroundStyle(SettingsDestination.personalization.iconColor)
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { PersonalizationFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif
