import SFSafeSymbols
import SwiftUI

/// A compact catalog of the four data-quality detectors Where runs, headed by
/// the report model's already-loaded live issue count.
struct FeatureDataAccuracyPreview: View {
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

                Label {
                    Text(status)
                        .font(.subheadline.bold())
                } icon: {
                    Image(systemSymbol: issueCount == 0 ? .checkmarkCircleFill :
                        .exclamationmarkCircleFill)
                        .foregroundStyle(issueCount == 0 ? .green : .orange)
                }

                Divider()

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
        }
        .accessibilityElement(children: .contain)
    }

    private var status: String {
        if issueCount == 0 {
            String(localized: .settingsExploreInsightsAllClear)
        } else {
            String(localized: .settingsExploreInsightsIssueCount(issueCount))
        }
    }

    private func detector(_ title: String, icon: SFSymbol) -> some View {
        Label(title, systemSymbol: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview {
        FeatureDataAccuracyPreview(issueCount: 4)
            .padding()
            .whereBroadwayRoot()
    }
#endif
