import SwiftUI

/// Shared safe-area footer. The page owns scrolling; actions remain reachable.
struct OnboardingFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.spacing.medium, content: content)
            .padding(.horizontal, stylesheet.onboarding.padding)
            .padding(.vertical, stylesheet.spacing.large)
            .frame(maxWidth: stylesheet.onboarding.maxWidth)
            .frame(maxWidth: .infinity)
            .background {
                Color(uiColor: .systemGroupedBackground)
                    .opacity(stylesheet.onboarding.footer.backgroundOpacity)
                    .ignoresSafeArea(edges: .bottom)
            }
    }
}

#if DEBUG
    #Preview {
        OnboardingFooter {
            OnboardingAction(title: .onboardingContinue, action: {})
            OnboardingAction(title: .onboardingBack, prominence: .secondary, action: {})
        }
        .whereBroadwayRoot()
    }
#endif
