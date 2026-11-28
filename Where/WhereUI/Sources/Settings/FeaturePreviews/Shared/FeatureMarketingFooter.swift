import SwiftUI

struct FeatureMarketingFooter: View {
    let detail: LocalizedStringResource
    let order: Int

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(String(localized: detail))
            FeatureDiscoveryDataFooter()
        }
        .staggeredReveal(order: order)
    }
}

#if DEBUG
    #Preview {
        FeatureMarketingFooter(detail: .settingsExploreInsightsFooter, order: 0)
            .whereBroadwayRoot()
    }
#endif
