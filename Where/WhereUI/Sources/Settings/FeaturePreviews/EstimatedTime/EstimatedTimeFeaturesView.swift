import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Explains Where's annual projection and the planned-stay adjustment using
/// the user's live report whenever it is eligible.
struct EstimatedTimeFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                Form {
                    FeatureMarketingHeader(
                        title: String(localized: .settingsExploreEstimatedTimeTitle),
                        tagline: String(localized: .settingsExploreEstimatedTimeTagline),
                        systemSymbol: SettingsDestination.estimatedTime.systemSymbol,
                        tint: SettingsDestination.estimatedTime.iconColor,
                    )
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .staggeredReveal(order: 0)

                    Section {
                        preview
                            .featureMarketingRow(order: 1)
                            .settingsRow(Item.overview, restingBackground: .clear)
                    }

                    Section {
                        explanation(
                            title: String(localized: .settingsExploreEstimatedTimePaceTitle),
                            body: String(localized: .settingsExploreEstimatedTimePaceDescription),
                            systemSymbol: .chartLineUptrendXyaxis,
                        )
                        .featureMarketingRow(order: 2)
                        .settingsRow(Item.pace, restingBackground: .clear)

                        explanation(
                            title: String(localized: .settingsExploreEstimatedTimePlanTitle),
                            body: String(localized: .settingsExploreEstimatedTimePlanDescription),
                            systemSymbol: .calendarBadgeClock,
                        )
                        .featureMarketingRow(order: 3)
                        .settingsRow(Item.planning, restingBackground: .clear)
                    }

                    Section {
                        FeatureEstimatedTimeCalculationExample()
                            .featureMarketingRow(order: 4)
                            .settingsRow(Item.calculation, restingBackground: .clear)
                    }

                    Section {
                        explanation(
                            title: String(localized: .settingsExploreEstimatedTimeTotalsTitle),
                            body: String(localized: .settingsExploreEstimatedTimeTotalsDescription),
                            systemSymbol: .airplane,
                        )
                        .featureMarketingRow(order: 5)
                        .settingsRow(Item.totals, restingBackground: .clear)
                    }

                    Section {
                        FeatureMarketingPanel {
                            NavigationLink(value: SettingsRoute(.appearance)) {
                                Label {
                                    Text(String(localized: .settingsExploreEstimatedTimeManage))
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemSymbol: .paintbrushFill)
                                        .foregroundStyle(SettingsDestination.estimatedTime
                                            .iconColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .featureMarketingRow(order: 6)
                    } footer: {
                        FeatureDiscoveryDataFooter()
                            .staggeredReveal(order: 7)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FeatureDiscoveryBackground())
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var preview: some View {
        if !report.showsEstimatedTimeAndPlanning {
            FeatureEstimatedTimeStatusPreview(state: .disabled)
        } else if forecasts.isEmpty {
            FeatureEstimatedTimeStatusPreview(state: .unavailable)
        } else {
            LocationForecastPanel(
                forecasts: forecasts,
                plannedStay: report.forecasts.activePlannedStay,
            )
        }
    }

    private var forecasts: [LocationForecast] {
        report.forecasts.leadingForecasts(report: report.report)
    }

    private func explanation(
        title: String,
        body: String,
        systemSymbol: SFSymbol,
    ) -> some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                Label(title, systemSymbol: systemSymbol)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension EstimatedTimeFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .estimatedTime
    }

    enum Item: SettingsItem {
        case overview
        case pace
        case planning
        case calculation
        case totals

        var title: String {
            switch self {
                case .overview: String(localized: .settingsExploreEstimatedTimeOverview)
                case .pace: String(localized: .settingsExploreEstimatedTimePaceTitle)
                case .planning: String(localized: .settingsExploreEstimatedTimePlanTitle)
                case .calculation:
                    String(localized: .settingsExploreEstimatedTimeCalculationTitle)
                case .totals: String(localized: .settingsExploreEstimatedTimeTotalsTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsEstimatedTimeFeatures))
        }
    }
}

#if DEBUG
    extension EstimatedTimeFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Live",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                EstimatedTimeFeaturesView(
                    report: PreviewSupport.plannedStayYearReportModel(),
                    focus: nil,
                )
            }
            whereSnapshot(
                name: "Unavailable",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                EstimatedTimeFeaturesView(
                    report: PreviewSupport.emptyYearReportModel(),
                    focus: nil,
                )
            }
            whereSnapshot(
                name: "Disabled",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                EstimatedTimeFeaturesView(
                    report: PreviewSupport.loadedYearReportModelWithEstimatedTimeHidden(),
                    focus: nil,
                )
            }
        }
    }

    #Preview {
        NavigationStack { EstimatedTimeFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }

    extension EstimatedTimeFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            EstimatedTimeFeaturesView.self,
            title: "Estimated Time & Planning",
            routes: [.push(to: AppearanceSettingsView.flyoverID)],
        )
    }
#endif
