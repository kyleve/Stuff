import SFSafeSymbols
import SwiftUI

/// A deterministic preview of the private on-device activity narrative. The
/// real Foundation Models generation starts only after the user opens it.
struct FeatureRecentActivityPreview: View {
    let example: FeatureDiscoveryPresentation.ActivityExample

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                Label(
                    String(localized: .settingsExploreInsightsActivityTitle),
                    systemSymbol: .sparkles,
                )
                .font(.headline)

                Text(example.summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    String(localized: .settingsExploreInsightsOnDevice),
                    systemSymbol: .iphoneGen3RadiowavesLeftAndRight,
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        FeatureRecentActivityPreview(
            example: .init(summary: "Your latest 14 logged days include California and New York."),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
