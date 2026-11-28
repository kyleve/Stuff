import SnapshotKit
import SwiftUI

struct EstimatedTimeSurfacesSection: View {
    let report: YearReportModel
    let showPlanner: () -> Void

    var body: some View {
        Section {
            FeatureGuidePanel(
                title: .settingsExploreEstimatedTimeSurfacesTitle,
                detail: .settingsExploreEstimatedTimeSurfacesDetail,
                symbol: .calendarDayTimelineLeft,
            ) {
                PresenceTimelineList(report: report, presentation: .excerpt)
            }
            .featureMarketingRow(order: 6)
            .settingsRow(EstimatedTimeFeaturesView.Item.surfaces, restingBackground: .clear)
            FeatureMarketingPanel {
                FeatureMarketingActionButton(
                    title: .settingsExploreEstimatedTimeManage,
                    symbol: .paintbrushFill,
                    tint: SettingsDestination.estimatedTime.iconColor,
                    action: showPlanner,
                )
            }
            .featureMarketingRow(order: 7)
            FeatureSettingsLink(destination: .appearance).featureMarketingRow(order: 8)
        } footer: {
            FeatureDiscoveryDataFooter()
                .staggeredReveal(order: 9)
        }
    }
}

#if DEBUG
    #Preview { NavigationStack { EstimatedTimeFeaturesView.snapshotPreviews }.whereBroadwayRoot() }
#endif
