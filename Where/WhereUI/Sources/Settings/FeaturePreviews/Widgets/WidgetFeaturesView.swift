import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A visual catalog of every widget family Where currently offers, grouped on
/// the system surface where the user can add it.
struct WidgetFeaturesView: View {
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                Form {
                    FeatureMarketingHeader(
                        title: String(localized: .settingsExploreWidgetsTitle),
                        tagline: String(localized: .settingsExploreWidgetsTagline),
                        systemSymbol: SettingsDestination.widgets.systemSymbol,
                        tint: SettingsDestination.widgets.iconColor,
                    )
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .staggeredReveal(order: 0)

                    Section {
                        FeatureHomeScreenExample(snapshot: presentation.widgetSnapshot)
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                            .settingsRow(Item.homeScreen, restingBackground: .clear)
                            .staggeredReveal(order: 1)
                    } header: {
                        Text(String(localized: .settingsExploreWidgetsHomeHeader))
                            .staggeredReveal(order: 1)
                    } footer: {
                        Text(String(localized: .settingsExploreWidgetsHomeFooter))
                            .staggeredReveal(order: 1)
                    }

                    Section {
                        FeatureLockScreenExample(
                            date: presentation.lockScreenDate,
                            snapshot: presentation.widgetSnapshot,
                        )
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                        .settingsRow(Item.lockScreen, restingBackground: .clear)
                        .staggeredReveal(order: 2)
                    } header: {
                        Text(String(localized: .settingsExploreWidgetsLockHeader))
                            .staggeredReveal(order: 2)
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExploreWidgetsLockFooter))
                                .staggeredReveal(order: 2)
                            FeatureDiscoveryDataFooter()
                                .staggeredReveal(order: 3)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FeatureDiscoveryBackground())
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension WidgetFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .widgets
    }

    enum Item: SettingsItem {
        case homeScreen
        case lockScreen

        var title: String {
            switch self {
                case .homeScreen: String(localized: .settingsExploreWidgetsHomeHeader)
                case .lockScreen: String(localized: .settingsExploreWidgetsLockHeader)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsWidgets))
        }
    }
}

#if DEBUG
    extension WidgetFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                WidgetFeaturesView(
                    focus: nil,
                    presentation: PreviewSupport.featureDiscoveryPresentation(),
                )
            }
            whereSnapshot(
                name: "TwoRegions",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                WidgetFeaturesView(
                    focus: nil,
                    presentation: twoRegionPresentation,
                )
            }
        }

        private static var twoRegionPresentation: FeatureDiscoveryPresentation {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let report = PreviewSupport.sampleReport()
            return FeatureDiscoveryPresentation(
                report: YearReport(
                    year: report.year,
                    days: report.days,
                    totals: [
                        .newYork: 121,
                        .california: 104,
                    ],
                ),
                selectedYear: report.year,
                referenceDate: PreviewSupport.referenceNow,
                calendar: calendar,
            )
        }
    }

    #Preview {
        NavigationStack {
            WidgetFeaturesView(
                focus: nil,
                presentation: PreviewSupport.featureDiscoveryPresentation(),
            )
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension WidgetFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            WidgetFeaturesView.self,
            title: "Widgets",
        )
    }
#endif
