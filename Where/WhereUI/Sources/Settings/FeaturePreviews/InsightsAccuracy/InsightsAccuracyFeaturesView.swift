import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Markets Where's automatic data-quality detection while deferring fixes
/// until an explicit action.
struct InsightsAccuracyFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?

    @State private var showingResolution = false
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                Form {
                    FeatureMarketingHeader(
                        title: String(localized: .settingsExploreInsightsTitle),
                        tagline: String(localized: .settingsExploreInsightsTagline),
                        systemSymbol: SettingsDestination.insightsAccuracy.systemSymbol,
                        tint: SettingsDestination.insightsAccuracy.iconColor,
                    )
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .staggeredReveal(order: 0)

                    Section {
                        FeatureDataAccuracyPreview(issueCount: report.dataIssueCount)
                            .featureMarketingRow(order: 1)
                            .settingsRow(Item.dataAccuracy, restingBackground: .clear)

                        if report.dataIssueCount > 0 {
                            FeatureMarketingPanel {
                                Button(action: showResolution) {
                                    actionLabel(
                                        String(localized: .settingsExploreInsightsOpenResolve),
                                        systemSymbol: .checklist,
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .featureMarketingRow(order: 2)
                        }
                    }
                    Section {
                        FeatureGuidePanel(
                            title: .settingsExploreInsightsCorrectionsTitle,
                            detail: .settingsExploreInsightsCorrectionsDetail,
                            symbol: .checklist,
                        ) {}
                            .featureMarketingRow(order: 3)
                            .settingsRow(Item.corrections, restingBackground: .clear)
                        FeatureSettingsLink(destination: .loggedDays).featureMarketingRow(order: 4)
                        FeatureGuidePanel(
                            title: .settingsExploreInsightsAlertsTitle,
                            detail: .settingsExploreInsightsAlertsDetail,
                            symbol: .bellBadge,
                        ) {}
                            .featureMarketingRow(order: 5)
                            .settingsRow(Item.alerts, restingBackground: .clear)
                        FeatureSettingsLink(destination: .alerts).featureMarketingRow(order: 6)
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExploreInsightsFooter))
                            FeatureDiscoveryDataFooter()
                        }
                        .staggeredReveal(order: 7)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FeatureDiscoveryBackground())
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingResolution) {
            ResolutionView(report: report)
        }
    }

    private func actionLabel(_ title: String, systemSymbol: SFSymbol) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemSymbol: systemSymbol)
                .foregroundStyle(SettingsDestination.insightsAccuracy.iconColor)
        }
    }

    private func showResolution() {
        showingResolution = true
    }
}

extension InsightsAccuracyFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .insightsAccuracy
    }

    enum Item: SettingsItem {
        case dataAccuracy
        case corrections
        case alerts

        var title: String {
            switch self {
                case .dataAccuracy: String(localized: .settingsExploreInsightsAccuracyTitle)
                case .corrections: String(localized: .settingsExploreInsightsCorrectionsTitle)
                case .alerts: String(localized: .settingsExploreInsightsAlertsTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsInsightsFeatures))
        }
    }
}

#if DEBUG
    extension InsightsAccuracyFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                InsightsAccuracyFeaturesView(
                    report: reportWithIssues(),
                    focus: nil,
                )
            }
            whereSnapshot(
                name: "NoIssues",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                InsightsAccuracyFeaturesView(
                    report: PreviewSupport.emptyYearReportModel(),
                    focus: nil,
                )
            }
        }

        private static func reportWithIssues() -> YearReportModel {
            let report = PreviewSupport.loadedYearReportModel()
            report.setDataIssueCount(4)
            return report
        }
    }

    #Preview {
        NavigationStack { InsightsAccuracyFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension InsightsAccuracyFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            InsightsAccuracyFeaturesView.self,
            title: "Insights & Accuracy",
            routes: [
                .modal(to: ResolutionView.flyoverID),
                .push(to: LoggedDaysView.flyoverID),
                .push(to: AlertsSettingsView.flyoverID),
            ],
        )
    }
#endif
