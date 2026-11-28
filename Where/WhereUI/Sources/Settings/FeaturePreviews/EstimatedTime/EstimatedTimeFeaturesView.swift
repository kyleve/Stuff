import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Explains Where's annual projection and the planned-stay adjustment using
/// the user's live report whenever it is eligible.
struct EstimatedTimeFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                EstimatedTimeFeaturesContent(report: report)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
        case surfaces

        var title: String {
            switch self {
                case .overview: String(localized: .settingsExploreEstimatedTimeOverview)
                case .pace: String(localized: .settingsExploreEstimatedTimePaceTitle)
                case .planning: String(localized: .settingsExploreEstimatedTimePlanTitle)
                case .calculation:
                    String(localized: .settingsExploreEstimatedTimeCalculationTitle)
                case .surfaces: String(localized: .settingsExploreEstimatedTimeSurfacesTitle)
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
                configurations: .fullContentPhoneLightDarkWithAX5,
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
            routes: [
                .push(to: AppearanceSettingsView.flyoverID),
                .modal(to: PlannedStaysView.flyoverID),
            ],
        )
    }
#endif
