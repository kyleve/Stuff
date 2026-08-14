import SwiftUI

/// Presents one active privacy-reporting disclosure as a self-contained status row.
struct PrivacyPassportDisclosureRow: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let interaction: PrivacyPassportDisclosureInteraction

    @Environment(\.isInDemoMode) private var isInDemoMode

    var body: some View {
        if interaction == .linkToSettings, !isInDemoMode {
            NavigationLink(value: SettingsRoute(.privacyDiagnostics)) {
                PrivacyPassportDisclosureRowLabel(
                    disclosure: disclosure,
                    showsSettingsIndicator: true,
                )
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
        } else {
            PrivacyPassportDisclosureRowLabel(
                disclosure: disclosure,
                showsSettingsIndicator: false,
            )
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            PrivacyPassportCardSurface(tilt: .preview) {
                PrivacyPassportDisclosureRow(
                    disclosure: .crashReports,
                    interaction: .linkToSettings,
                )
                .padding()
            }
            .padding()
        }
        .whereBroadwayRoot()
    }
#endif
