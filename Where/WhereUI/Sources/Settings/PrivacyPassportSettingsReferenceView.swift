import SwiftUI

/// Links to the sharing controls or identifies their location on the current screen.
struct PrivacyPassportSettingsReferenceView: View {
    let reference: PrivacyPassportSettingsReference

    @Environment(\.isInDemoMode) private var isInDemoMode

    var body: some View {
        if reference == .link, !isInDemoMode {
            NavigationLink(value: SettingsRoute(.privacyDiagnostics)) {
                PrivacyPassportSettingsReferenceLabel(
                    detail: .settingsPrivacySettingsAction,
                )
            }
            .buttonStyle(.plain)
        } else {
            PrivacyPassportSettingsReferenceLabel(
                detail: reference == .controlsBelow ?
                    .settingsPrivacySettingsBelow : .settingsPrivacySettingsUnavailable,
            )
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            PrivacyPassportCardSurface(tilt: .preview) {
                PrivacyPassportSettingsReferenceView(reference: .link)
                    .padding()
            }
            .padding()
        }
        .whereBroadwayRoot()
    }
#endif
