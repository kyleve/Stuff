import SwiftUI

/// A lightweight device silhouette around read-only production views.
/// Content can grow vertically with Dynamic Type instead of being scaled or clipped.
struct OnboardingPhoneFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.onboarding.phone
        VStack(spacing: style.contentSpacing) {
            Capsule()
                .fill(.primary.opacity(style.hardwareOpacity))
                .frame(width: style.cameraWidth, height: style.cameraHeight)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
            Capsule()
                .fill(.primary.opacity(style.hardwareOpacity))
                .frame(width: style.homeWidth, height: style.homeHeight)
                .accessibilityHidden(true)
        }
        .padding(style.padding)
        .frame(maxWidth: style.width, minHeight: style.minHeight)
        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: style.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .strokeBorder(.primary.opacity(style.borderOpacity), lineWidth: style.borderWidth)
                .allowsHitTesting(false)
        }
        .shadow(
            color: .black.opacity(style.shadowOpacity),
            radius: style.shadowRadius,
            y: style.shadowY,
        )
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
    #Preview {
        OnboardingPhoneFrame { Text(.onboardingWelcomeTitle) }.padding().whereBroadwayRoot()
    }
#endif
