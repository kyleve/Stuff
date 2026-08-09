import SwiftUI

struct PatchlightOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(String(localized: .connectToGitHub))
                    .font(.largeTitle.bold())
                Text(String(localized: .githubOnboardingDescription))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Label(String(localized: .githubPermissionsSummary), systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: .deviceFlowComingNext)) {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(40)
            .frame(maxWidth: 680, minHeight: 500)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .cancel)) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PatchlightOnboardingView()
        .patchlightBroadwayRoot()
}
