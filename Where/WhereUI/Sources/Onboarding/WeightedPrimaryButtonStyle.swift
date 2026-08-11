import SwiftUI

/// A restrained primary action that responds immediately, then settles like a
/// small physical control without elastic overshoot.
struct WeightedPrimaryButtonStyle: ButtonStyle {
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let onboarding = stylesheet.onboarding
        configuration.label
            .font(.headline)
            .foregroundStyle(stylesheet.palette.brand.onMidnight)
            .padding(.vertical, onboarding.primaryButtonVerticalPadding)
            .padding(.horizontal, stylesheet.spacing.xxxLarge)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                stylesheet.palette.brand.midnight,
                in: RoundedRectangle(cornerRadius: onboarding.primaryButtonCornerRadius),
            )
            .scaleEffect(
                reduceMotion || !configuration.isPressed
                    ? 1
                    : onboarding.primaryButtonPressedScale,
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.16),
                radius: configuration.isPressed ? 4 : 10,
                y: configuration.isPressed ? 2 : 6,
            )
            .animation(
                reduceMotion ? stylesheet.motion.reduced : stylesheet.motion.response,
                value: configuration.isPressed,
            )
    }
}

#if DEBUG
    #Preview {
        Button("Continue") {}
            .buttonStyle(WeightedPrimaryButtonStyle())
            .padding()
            .whereBroadwayRoot()
    }
#endif
