import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// A feature-marketing gallery for the region appearance and alternate app-icon
/// systems, with links into their existing editors.
struct PersonalizationFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?

    @State private var iconModel: AppIconModel
    @State private var presentedSheet: Sheet?
    @Environment(\.isInDemoMode) private var isInDemoMode
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.stylesheet) private var stylesheet

    @MainActor
    init(
        report: YearReportModel,
        focus: SettingsFocus?,
        iconModel: AppIconModel = AppIconModel(),
    ) {
        self.report = report
        self.focus = focus
        _iconModel = State(initialValue: iconModel)
    }

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
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
                            .settingsRow(Item.regions, restingBackground: .clear)

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
                            .settingsRow(Item.appIcon, restingBackground: .clear)

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
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExplorePersonalizationFooter))
                            FeatureDiscoveryDataFooter()
                        }
                        .staggeredReveal(order: 5)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FeatureDiscoveryBackground())
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
                case .regions: RegionsSettingsView(usedThisYear: regionsUsedThisYear)
                case .appIcon: AppIconView(model: iconModel)
            }
        }
    }

    private var featuredRegion: Region {
        report.ranking.primary.first?.region ?? .california
    }

    private var featuredStyle: RegionStyle {
        regionStyles.style(for: featuredRegion)
    }

    private var regionsUsedThisYear: Set<Region> {
        guard let totals = report.report?.totals else { return [] }
        return Set(totals.filter { $0.key != .other && $0.value > 0 }.map(\.key))
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

    private func showRegions() {
        presentedSheet = .regions
    }

    private func showAppIcons() {
        presentedSheet = .appIcon
    }

    private enum Sheet: Hashable, Identifiable {
        case regions
        case appIcon

        var id: Self {
            self
        }
    }
}

extension PersonalizationFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .personalization
    }

    enum Item: SettingsItem {
        case regions
        case appIcon

        var title: String {
            switch self {
                case .regions: String(localized: .settingsExplorePersonalizationRegionsTitle)
                case .appIcon: String(localized: .settingsExplorePersonalizationIconTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsPersonalizationFeatures))
        }
    }
}

#if DEBUG
    extension PersonalizationFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                PersonalizationFeaturesView(
                    report: PreviewSupport.loadedYearReportModel(),
                    focus: nil,
                    iconModel: .preview(activeAlternateIconName: "AppIconPride"),
                )
            }
        }
    }

    #Preview {
        NavigationStack { PersonalizationFeaturesView.snapshotPreviews }
            .whereBroadwayRoot(regionStyles: RegionStyleResolver(appearances: [
                .california: RegionAppearanceCatalog.defaultAppearance(for: .california),
            ]))
    }
#endif

#if DEBUG
    extension PersonalizationFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            PersonalizationFeaturesView.self,
            title: "Make It Yours",
            routes: [
                .modal(to: RegionsSettingsView.flyoverID),
                .modal(to: AppIconView.flyoverID),
            ],
        )
    }
#endif
