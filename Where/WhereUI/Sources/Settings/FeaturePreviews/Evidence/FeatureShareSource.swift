import SFSafeSymbols
import SwiftUI

struct FeatureShareSource: View {
    let systemSymbol: SFSymbol
    let title: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Group {
            if stylesheet.featureDiscovery.shareSheet.sourceLayout == .inline {
                HStack(spacing: stylesheet.spacing.small) {
                    sourceIcon(systemSymbol)
                    sourceTitle(
                        title,
                        alignment: stylesheet.featureDiscovery.shareSheet.titleAlignment,
                    )
                }
            } else {
                VStack(spacing: stylesheet.spacing.small) {
                    sourceIcon(systemSymbol)
                    sourceTitle(
                        title,
                        alignment: stylesheet.featureDiscovery.shareSheet.titleAlignment,
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceIcon(_ systemSymbol: SFSymbol) -> some View {
        Image(systemSymbol: systemSymbol)
            .font(.system(size: 22))
            .frame(width: 44, height: 44)
            .background(.quaternary, in: .rect(cornerRadius: 12))
    }

    private func sourceTitle(_ title: String, alignment: TextAlignment) -> some View {
        Text(title)
            .font(.caption)
            .multilineTextAlignment(alignment)
    }
}

#if DEBUG
    #Preview {
        FeatureShareSource(
            systemSymbol: .airplane,
            title: String(localized: .settingsExploreEvidenceSourcePass),
        )
        .whereBroadwayRoot()
    }
#endif
