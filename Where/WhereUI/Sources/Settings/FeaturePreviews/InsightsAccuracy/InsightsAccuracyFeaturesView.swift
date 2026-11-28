import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Markets Where's automatic data-quality detection while deferring fixes
/// until an explicit action.
struct InsightsAccuracyFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?

    @State private var showingResolution = false

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                InsightsAccuracyFeaturesContent(report: report, showResolution: showResolution)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingResolution) {
            ResolutionView(report: report)
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
                configurations: .fullContentPhoneLightDark,
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

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
private struct InsightsAccuracyFeaturesContent: View {
    let report: YearReportModel
    let showResolution: () -> Void

    var body: some View {
        Form {
            FeatureMarketingHeaderRow(
                title: String(localized: .settingsExploreInsightsTitle),
                tagline: .settingsExploreInsightsTagline,
                destination: .insightsAccuracy,
            )

            InsightsAccuracySection(
                issueCount: report.dataIssueCount,
                showResolution: showResolution,
            )
            InsightsCorrectionAndAlertsSection()
        }
        .whereFormRoot()
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }
}

private struct InsightsAccuracySection: View {
    let issueCount: Int
    let showResolution: () -> Void

    var body: some View {
        Section {
            FeatureDataAccuracyPreview(issueCount: issueCount)
                .featureMarketingRow(order: 1)
                .settingsRow(
                    InsightsAccuracyFeaturesView.Item.dataAccuracy,
                    restingBackground: .clear,
                )

            if issueCount > 0 {
                FeatureMarketingPanel {
                    FeatureMarketingActionButton(
                        title: .settingsExploreInsightsOpenResolve,
                        symbol: .checklist,
                        tint: SettingsDestination.insightsAccuracy.iconColor,
                        action: showResolution,
                    )
                }
                .featureMarketingRow(order: 2)
            }
        }
    }
}

/// A compact catalog of the four data-quality detectors Where runs, headed by
/// the report model's already-loaded live issue count.
private struct FeatureDataAccuracyPreview: View {
    let issueCount: Int

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                Label(
                    String(localized: .settingsExploreInsightsAccuracyTitle),
                    systemSymbol: .checkmarkShield,
                )
                .font(.headline)

                DataAccuracyStatus(issueCount: issueCount)

                Divider()

                DataAccuracyDetectors()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DataAccuracyStatus: View {
    let issueCount: Int

    var body: some View {
        Label {
            Text(status)
                .font(.subheadline.bold())
        } icon: {
            Image(systemSymbol: issueCount == 0 ? .checklist :
                .exclamationmarkCircleFill)
                .foregroundStyle(issueCount == 0 ? Color.secondary : Color.orange)
        }
    }

    private var status: String {
        if issueCount == 0 {
            String(localized: .settingsExploreInsightsReviewStatus)
        } else {
            String(localized: .settingsExploreInsightsIssueCount(issueCount))
        }
    }
}

private struct DataAccuracyDetectors: View {
    var body: some View {
        detector(
            String(localized: .settingsExploreInsightsMissingDays),
            icon: .calendarBadgeExclamationmark,
        )
        detector(
            String(localized: .settingsExploreInsightsBorderDrift),
            icon: .locationCircle,
        )
        detector(
            String(localized: .settingsExploreInsightsAbruptChanges),
            icon: .arrowTriangleSwap,
        )
        detector(String(localized: .settingsExploreInsightsFlightDays), icon: .airplane)
    }

    private func detector(_ title: String, icon: SFSymbol) -> some View {
        Label(title, systemSymbol: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview("FeatureDataAccuracyPreview") {
        FeatureDataAccuracyPreview(issueCount: 4)
            .padding()
            .whereBroadwayRoot()
    }
#endif
