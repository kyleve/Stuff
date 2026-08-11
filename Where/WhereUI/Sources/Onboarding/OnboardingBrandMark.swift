import SFSafeSymbols
import SwiftUI

/// The quiet cartographic seal that anchors Where's first-run pages.
struct OnboardingBrandMark: View {
    let systemSymbol: SFSymbol

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.onboarding
        ZStack {
            Circle()
                .strokeBorder(stylesheet.palette.brand.brass, lineWidth: 1.5)
            Circle()
                .strokeBorder(
                    stylesheet.palette.brand.brass.opacity(0.55),
                    style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]),
                )
                .padding(7)
            Image(systemSymbol: systemSymbol)
                .font(stylesheet.typography.onboardingIcon)
                .foregroundStyle(stylesheet.palette.brand.ink)
        }
        .frame(width: style.brandMarkSize, height: style.brandMarkSize)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        OnboardingBrandMark(systemSymbol: .globeAmericasFill)
            .padding()
            .whereBroadwayRoot()
    }
#endif
