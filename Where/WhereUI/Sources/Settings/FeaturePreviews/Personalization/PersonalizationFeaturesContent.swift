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

    @Environment(\.isInDemoMode) private var isInDemoMode
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        Form {
            FeatureMarketingHeaderRow(
                title: String(localized: .settingsExplorePersonalizationTitle),
                tagline: .settingsExplorePersonalizationTagline,
                destination: .personalization,
            )

            PersonalizationRegionSection(
                region: featuredRegion,
                style: featuredStyle,
                showRegions: showRegions,
            )

            PersonalizationIconSection(
                iconModel: iconModel,
                isInDemoMode: isInDemoMode,
                showAppIcons: showAppIcons,
            )
            PersonalizationAppearanceSection()
        }
        .whereFormRoot()
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }

    private var featuredRegion: Region {
        report.ranking.primary.first?.region ?? .california
    }

    private var featuredStyle: RegionStyle {
        regionStyles.style(for: featuredRegion)
    }
}

private struct PersonalizationRegionSection: View {
    let region: Region
    let style: RegionStyle
    let showRegions: () -> Void

    var body: some View {
        Section {
            FeatureRegionStylePreview(region: region, style: style)
                .featureMarketingRow(order: 1)
                .settingsRow(
                    PersonalizationFeaturesView.Item.regions,
                    restingBackground: .clear,
                )

            FeatureMarketingPanel {
                FeatureMarketingActionButton(
                    title: .settingsExplorePersonalizationOpenRegions,
                    symbol: .paintpalette,
                    tint: SettingsDestination.personalization.iconColor,
                    action: showRegions,
                )
            }
            .featureMarketingRow(order: 2)
        }
    }
}

private struct PersonalizationIconSection: View {
    let iconModel: AppIconModel
    let isInDemoMode: Bool
    let showAppIcons: () -> Void

    var body: some View {
        Section {
            FeatureAppIconPreview(model: iconModel)
                .featureMarketingRow(order: 3)
                .settingsRow(
                    PersonalizationFeaturesView.Item.appIcon,
                    restingBackground: .clear,
                )

            if !isInDemoMode {
                FeatureMarketingPanel {
                    FeatureMarketingActionButton(
                        title: .settingsExplorePersonalizationOpenIcon,
                        symbol: .appBadge,
                        tint: SettingsDestination.personalization.iconColor,
                        action: showAppIcons,
                    )
                }
                .featureMarketingRow(order: 4)
            }
        }
    }
}

private struct PersonalizationAppearanceSection: View {
    var body: some View {
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
            FeatureMarketingFooter(detail: .settingsExplorePersonalizationFooter, order: 7)
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { PersonalizationFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif

/// Shows the icon iOS currently has selected, sourced from the same manifest and
/// live system value as the full app-icon picker.
private struct FeatureAppIconPreview: View {
    let model: AppIconModel

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                Label(
                    String(localized: .settingsExplorePersonalizationIconTitle),
                    systemSymbol: .appBadge,
                )
                .font(.headline)

                if let selected = model.selectedOption {
                    SelectedAppIconPreview(option: selected)
                } else {
                    ContentUnavailableView(
                        String(localized: .settingsExplorePersonalizationIconUnavailable),
                        systemSymbol: .appDashed,
                    )
                }
            }
        }
    }
}

private struct SelectedAppIconPreview: View {
    let option: AppIconOption

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        selectedLayout {
            AppIconImage(name: option.previewImageName, size: 76)
            VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                Text(option.displayName)
                    .font(.title3.bold())
                Text(String(localized: .settingsExplorePersonalizationCurrentIcon))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var selectedLayout: AnyLayout {
        if stylesheet.featureDiscovery.appIcon.layout == .stacked {
            AnyLayout(VStackLayout(
                alignment: .leading,
                spacing: stylesheet.featureDiscovery.appIcon.spacing,
            ))
        } else {
            AnyLayout(HStackLayout(spacing: stylesheet.featureDiscovery.appIcon.spacing))
        }
    }
}

#if DEBUG
    #Preview("FeatureAppIconPreview") {
        FeatureAppIconPreview(model: .preview(activeAlternateIconName: "AppIconPride"))
            .padding()
            .whereBroadwayRoot()
    }
#endif

/// Shows one region's resolved user appearance across the surfaces that share it.
private struct FeatureRegionStylePreview: View {
    let region: Region
    let style: RegionStyle

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                PersonalizationRegionHeading(region: region, style: style)

                PersonalizationRegionSamples(style: style)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PersonalizationRegionHeading: View {
    let region: Region
    let style: RegionStyle

    var body: some View {
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
    }
}

private struct PersonalizationRegionSamples: View {
    let style: RegionStyle

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        previewLayout {
            PersonalizationRegionSample(
                title: String(localized: .settingsExplorePersonalizationCards),
                systemSymbol: style.symbol,
                style: style,
            )
            PersonalizationRegionSample(
                title: String(localized: .settingsExplorePersonalizationCalendar),
                systemSymbol: .calendar,
                style: style,
            )
            PersonalizationRegionSample(
                title: String(localized: .settingsExplorePersonalizationWidgets),
                systemSymbol: .widgetSmall,
                style: style,
            )
        }
    }

    private var previewLayout: AnyLayout {
        if stylesheet.featureDiscovery.regionStyle.layout == .stacked {
            AnyLayout(VStackLayout(
                alignment: .leading,
                spacing: stylesheet.featureDiscovery.regionStyle.spacing,
            ))
        } else {
            AnyLayout(HStackLayout(spacing: stylesheet.featureDiscovery.regionStyle.spacing))
        }
    }
}

private struct PersonalizationRegionSample: View {
    let title: String
    let systemSymbol: SFSymbol
    let style: RegionStyle

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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
    #Preview("FeatureRegionStylePreview") {
        FeatureRegionStylePreview(
            region: .california,
            style: RegionStyle(RegionAppearanceCatalog.defaultAppearance(for: .california)),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
