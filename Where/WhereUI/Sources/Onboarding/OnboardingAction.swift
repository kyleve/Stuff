import SwiftUI

/// The first-run primary action, with an opaque accessibility alternative.
struct OnboardingAction: View {
    let title: LocalizedStringResource
    let action: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        if stylesheet.onboarding.usesOpaqueSurfaces {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.glassProminent)
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }
}

#if DEBUG
    #Preview {
        OnboardingAction(title: .onboardingContinue, action: {}).padding().whereBroadwayRoot()
    }
#endif
