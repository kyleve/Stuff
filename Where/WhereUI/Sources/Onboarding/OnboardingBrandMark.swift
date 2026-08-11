import SwiftUI

/// The quiet cartographic seal that anchors Where's first-run pages.
struct OnboardingBrandMark: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        WhereSeal(tint: stylesheet.palette.brand.ink)
            .frame(
                width: stylesheet.onboarding.brandMarkSize,
                height: stylesheet.onboarding.brandMarkSize,
            )
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        OnboardingBrandMark()
            .padding()
            .whereBroadwayRoot()
    }
#endif
