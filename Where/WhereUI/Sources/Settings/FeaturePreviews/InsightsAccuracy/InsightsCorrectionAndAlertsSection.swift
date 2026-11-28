import SnapshotKit
import SwiftUI

struct InsightsCorrectionAndAlertsSection: View {
    var body: some View {
        Section {
            FeatureGuidePanel(
                title: .settingsExploreInsightsCorrectionsTitle,
                detail: .settingsExploreInsightsCorrectionsDetail,
                symbol: .checklist,
            ) {}
                .featureMarketingRow(order: 3)
                .settingsRow(
                    InsightsAccuracyFeaturesView.Item.corrections,
                    restingBackground: .clear,
                )
            FeatureSettingsLink(destination: .loggedDays).featureMarketingRow(order: 4)
            FeatureGuidePanel(
                title: .settingsExploreInsightsAlertsTitle,
                detail: .settingsExploreInsightsAlertsDetail,
                symbol: .bellBadge,
            ) {}
                .featureMarketingRow(order: 5)
                .settingsRow(
                    InsightsAccuracyFeaturesView.Item.alerts,
                    restingBackground: .clear,
                )
            FeatureSettingsLink(destination: .alerts).featureMarketingRow(order: 6)
        } footer: {
            FeatureMarketingFooter(detail: .settingsExploreInsightsFooter, order: 7)
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { InsightsAccuracyFeaturesView.snapshotPreviews }.whereBroadwayRoot()
    }
#endif
