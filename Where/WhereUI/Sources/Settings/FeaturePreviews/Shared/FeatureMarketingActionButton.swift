import SFSafeSymbols
import SwiftUI

struct FeatureMarketingActionButton: View {
    let title: LocalizedStringResource
    let symbol: SFSymbol
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(String(localized: title))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemSymbol: symbol)
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        FeatureMarketingActionButton(
            title: .settingsExploreInsightsOpenResolve,
            symbol: .checklist,
            tint: SettingsDestination.insightsAccuracy.iconColor,
            action: {},
        )
        .whereBroadwayRoot()
    }
#endif
