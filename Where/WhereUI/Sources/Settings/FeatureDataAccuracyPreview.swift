import SwiftUI

/// A compact catalog of the four data-quality detectors Where runs, headed by
/// the report model's already-loaded live issue count.
struct FeatureDataAccuracyPreview: View {
    let issueCount: Int

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.featureDiscovery.cardSpacing) {
                Label(
                    String(localized: .settingsExploreInsightsAccuracyTitle),
                    systemImage: "checkmark.shield",
                )
                .font(.headline)

                Label {
                    Text(status)
                        .font(.subheadline.bold())
                } icon: {
                    Image(systemName: issueCount == 0 ? "checkmark.circle.fill" :
                        "exclamationmark.circle.fill")
                        .foregroundStyle(issueCount == 0 ? .green : .orange)
                }

                Divider()

                detector(
                    String(localized: .settingsExploreInsightsMissingDays),
                    icon: "calendar.badge.exclamationmark",
                )
                detector(
                    String(localized: .settingsExploreInsightsBorderDrift),
                    icon: "location.circle",
                )
                detector(
                    String(localized: .settingsExploreInsightsAbruptChanges),
                    icon: "arrow.triangle.swap",
                )
                detector(String(localized: .settingsExploreInsightsFlightDays), icon: "airplane")
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

    private func detector(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
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
