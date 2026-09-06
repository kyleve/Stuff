import SFSafeSymbols
import SwiftUI

struct WelcomeStepView: View {
    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            VStack(spacing: stylesheet.spacing.xLarge) {
                Spacer(minLength: stylesheet.spacing.large)
                Image(systemSymbol: .airplane)
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(spacing: stylesheet.spacing.medium) {
                    Text(.onboardingWelcomeTitle)
                        .font(.largeTitle.bold())
                    Text(.onboardingWelcomeDescription)
                        .foregroundStyle(.secondary)
                    Text(.aboutDisclaimer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: stylesheet.spacing.large)
            }
            .padding(stylesheet.spacing.xLarge)
            .frame(maxWidth: .infinity)
        }
    }
}
