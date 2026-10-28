import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
struct InsightsAccuracyFeaturesContent: View {
    let report: YearReportModel
    let showResolution: () -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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
                    .settingsRow(
                        InsightsAccuracyFeaturesView.Item.dataAccuracy,
                        restingBackground: .clear,
                    )

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

    private func actionLabel(_ title: String, systemSymbol: SFSymbol) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemSymbol: systemSymbol)
                .foregroundStyle(SettingsDestination.insightsAccuracy.iconColor)
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { InsightsAccuracyFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif
