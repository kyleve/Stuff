import SwiftUI

/// The first-run primary action, with an opaque accessibility alternative.
struct OnboardingAction: View {
    enum Prominence { case primary, secondary }

    let title: LocalizedStringResource
    var prominence: Prominence = .primary
    let action: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        switch prominence {
            case .primary:
                if stylesheet.onboarding.usesOpaqueSurfaces {
                    button.buttonStyle(.borderedProminent)
                } else {
                    button.buttonStyle(.glassProminent)
                }
            case .secondary:
                if stylesheet.onboarding.usesOpaqueSurfaces {
                    button.buttonStyle(.bordered)
                } else {
                    button.buttonStyle(.glass)
                }
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
