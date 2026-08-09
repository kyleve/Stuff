import SwiftUI

/// The shared hero treatment for Settings screens that market a feature rather
/// than configure it.
struct FeatureMarketingHeader: View {
    let title: String
    let tagline: String
    let systemImage: String
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.marketingHeader
        VStack(spacing: style.spacing) {
            Image(systemName: systemImage)
                .font(.system(size: style.symbolPointSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: style.badgeSize, height: style.badgeSize)
                .background(tint.opacity(style.badgeTintOpacity), in: .circle)
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(tagline)
                .font(.body)
                .foregroundStyle(.secondary)
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
            title: "Siri & Shortcuts",
            tagline: "Ask about where you’ve been, or log it hands-free.",
            systemImage: "waveform",
            tint: .pink,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
