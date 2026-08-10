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
                        systemImage: SettingsDestination.insightsAccuracy.systemImage,
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
                                        systemImage: "checklist",
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .featureMarketingRow(order: 2)
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExploreInsightsFooter))
                            FeatureDiscoveryDataFooter()
                        }
                        .staggeredReveal(order: 3)
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

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
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

        var title: String {
            String(localized: .settingsExploreInsightsAccuracyTitle)
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
            routes: [.modal(to: ResolutionView.flyoverID)],
        )
    }
#endif
