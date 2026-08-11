import SFSafeSymbols
import SwiftUI

/// The shared hero treatment for Settings screens that market a feature rather
/// than configure it.
struct FeatureMarketingHeader: View {
    let title: String
    let tagline: String
    let systemSymbol: SFSymbol
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.marketingHeader
        VStack(spacing: style.spacing) {
            ZStack(alignment: .bottomTrailing) {
                WhereSeal(tint: stylesheet.palette.brand.brass)
                    .frame(width: style.sealSize, height: style.sealSize)

                Image(systemSymbol: systemSymbol)
                    .font(.system(size: style.featureSymbolPointSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: style.featureBadgeSize, height: style.featureBadgeSize)
                    .background(stylesheet.palette.brand.raisedPaper, in: .circle)
                    .overlay {
                        Circle()
                            .stroke(tint.opacity(0.38), lineWidth: 0.75)
                    }
            }
            .accessibilityHidden(true)

            Text(title)
                .font(stylesheet.typography.editorialTitle)
                .foregroundStyle(stylesheet.palette.brand.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(tagline)
                .font(.body)
                .foregroundStyle(stylesheet.palette.brand.ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: style.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, style.verticalPadding)
    }
}

#if DEBUG
    #Preview {
        FeatureMarketingHeader(
            title: "Siri, Shortcuts & Spotlight",
            tagline: "Ask, automate, or search for where you’ve been.",
            systemSymbol: .waveform,
            tint: .pink,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
