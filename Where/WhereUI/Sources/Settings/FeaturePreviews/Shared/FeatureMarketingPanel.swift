import SwiftUI

/// A shared resting surface for a complete pane in the feature-marketing
/// galleries. It keeps new explorers aligned with the Siri cards without
/// coupling their content to a particular system feature.
struct FeatureMarketingPanel<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.marketingPanel
        content
            .padding(style.padding)
            .frame(
                maxWidth: style.maxWidth,
                alignment: .leading,
            )
            .background(
                .background,
                in: .rect(cornerRadius: style.cornerRadius),
            )
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
    #Preview {
        FeatureMarketingPanel {
            Label("Feature preview", systemImage: "sparkles")
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
