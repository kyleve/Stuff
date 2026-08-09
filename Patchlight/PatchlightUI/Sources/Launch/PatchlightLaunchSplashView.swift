import SwiftUI

struct PatchlightLaunchSplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "scope")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
            Text(String(localized: .patchlightTitle))
                .font(.largeTitle.bold())
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(String(localized: .preparingPatchlight))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview {
    PatchlightLaunchSplashView()
        .patchlightBroadwayRoot()
}
