import SwiftUI

/// A centered, full-area working state built from Where's stable seal, an
/// honest system activity indicator, and a caption. It does not imply measured
/// progress and contains no ambient or repeating brand animation.
struct AppIconLoadingView: View {
    let caption: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.spacing.xLarge) {
            WhereSeal(tint: stylesheet.palette.brand.brass)
                .frame(width: 72)
                .accessibilityHidden(true)
            SystemActivityIndicator(tint: stylesheet.palette.brand.ink)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
    }
}

#if DEBUG
    #Preview {
        AppIconLoadingView(caption: "Charting your year…")
    }
#endif
