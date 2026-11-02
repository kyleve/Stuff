import SwiftUI

/// Consistent editorial heading shared by first-run pages and setup steps.
struct OnboardingHeader: View {
    let title: String
    let detail: String
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        OnboardingHeader(
            title: String(localized: .onboardingWelcomeTitle),
            detail: String(localized: .onboardingWelcomeDescription),
        )
        .padding().whereBroadwayRoot()
    }
#endif
