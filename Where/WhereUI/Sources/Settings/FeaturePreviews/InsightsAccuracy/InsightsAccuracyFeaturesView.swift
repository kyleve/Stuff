import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Markets Where's on-device travel narrative and its automatic data-quality
/// detection, while deferring generation and fixes until an explicit action.
struct InsightsAccuracyFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    @State private var presentedSheet: Sheet?
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
                        FeatureRecentActivityPreview(example: presentation.activityExample)
                            .featureMarketingRow(order: 1)
                            .settingsRow(Item.recentActivity, restingBackground: .clear)

                        FeatureMarketingPanel {
                            Button(action: showRecentActivity) {
                                actionLabel(
                                    String(localized: .settingsExploreInsightsOpenActivity),
                                    systemSymbol: .sparkles,
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .featureMarketingRow(order: 2)
                    }

                    Section {
                        FeatureDataAccuracyPreview(issueCount: report.dataIssueCount)
                            .featureMarketingRow(order: 3)
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
                            .featureMarketingRow(order: 4)
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExploreInsightsFooter))
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
                case .recentActivity: RecentActivitySummaryView(report: report)
                case .resolution: ResolutionView(report: report)
            }
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

    private func showRecentActivity() {
        presentedSheet = .recentActivity
    }

    private func showResolution() {
        presentedSheet = .resolution
    }

    private enum Sheet: Hashable, Identifiable {
        case recentActivity
        case resolution

        var id: Self {
            self
        }
    }
}

extension InsightsAccuracyFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .insightsAccuracy
    }

    enum Item: SettingsItem {
        case recentActivity
        case dataAccuracy

        var title: String {
            switch self {
                case .recentActivity: String(localized: .settingsExploreInsightsActivityTitle)
                case .dataAccuracy: String(localized: .settingsExploreInsightsAccuracyTitle)
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
            whereSnapshot(name: "Default", configurations: .fullContentScreenDefaults) {
                InsightsAccuracyFeaturesView(
                    report: reportWithIssues(),
                    focus: nil,
                    presentation: PreviewSupport.featureDiscoveryPresentation(),
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
                .modal(to: RecentActivitySummaryView.flyoverID),
                .modal(to: ResolutionView.flyoverID),
            ],
        )
    }
#endif
