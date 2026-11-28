import SFSafeSymbols
import SwiftUI

struct FeatureGuideExplanationRow<Item: SettingsItem>: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbol: SFSymbol
    let item: Item
    let order: Int

    var body: some View {
        FeatureGuidePanel(title: title, detail: detail, symbol: symbol) {}
            .featureMarketingRow(order: order)
            .settingsRow(item, restingBackground: .clear)
    }
}

#if DEBUG
    #Preview {
        FeatureGuideExplanationRow(
            title: .settingsExplorePlacesWelcomeTitle,
            detail: .settingsExplorePlacesWelcomeDetail,
            symbol: .sparkles,
            item: PlacesYearFeaturesView.Item.welcome,
            order: 4,
        ).whereBroadwayRoot()
    }
#endif
