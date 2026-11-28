import SFSafeSymbols
import SwiftUI

struct FeatureShareSourceList: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Group {
            if stylesheet.featureDiscovery.shareSheet.sourcesLayout == .stacked {
                VStack(
                    alignment: .leading,
                    spacing: stylesheet.featureDiscovery.shareSheet.sourcesSpacing,
                ) {
                    FeatureShareSource(
                        systemSymbol: .airplane,
                        title: String(localized: .settingsExploreEvidenceSourcePass),
                    )
                    FeatureShareSource(
                        systemSymbol: .docRichtext,
                        title: String(localized: .settingsExploreEvidenceSourceReceipt),
                    )
                    FeatureShareSource(
                        systemSymbol: .photo,
                        title: String(localized: .settingsExploreEvidenceSourcePhoto),
                    )
                }
            } else {
                HStack(spacing: stylesheet.featureDiscovery.shareSheet.sourcesSpacing) {
                    FeatureShareSource(
                        systemSymbol: .airplane,
                        title: String(localized: .settingsExploreEvidenceSourcePass),
                    )
                    FeatureShareSource(
                        systemSymbol: .docRichtext,
                        title: String(localized: .settingsExploreEvidenceSourceReceipt),
                    )
                    FeatureShareSource(
                        systemSymbol: .photo,
                        title: String(localized: .settingsExploreEvidenceSourcePhoto),
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
    #Preview {
        FeatureShareSourceList()
            .whereBroadwayRoot()
    }
#endif
