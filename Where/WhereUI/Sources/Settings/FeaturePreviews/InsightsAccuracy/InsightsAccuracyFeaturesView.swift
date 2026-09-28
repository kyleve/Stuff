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
