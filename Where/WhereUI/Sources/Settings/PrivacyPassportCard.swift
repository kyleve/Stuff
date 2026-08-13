import SwiftUI

/// Reassures the reader that Where's location history stays in their Apple storage.
struct PrivacyPassportCard: View {
    let presentation: PrivacyPassportPresentation
    @State private var tilt = TiltProvider()

    var body: some View {
        PassportCard(
            title: .settingsPrivacyTitle,
            detail: presentation.detail,
            sealSystemSymbol: .lockShieldFill,
            accessorySystemSymbol: nil,
            isInteractive: false,
            surface: .reflective(tilt: tilt),
        )
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }
}

#if DEBUG
    #Preview {
        Form {
            PrivacyPassportCard(presentation: PrivacyPassportPresentation(
                configuration: .defaults(isDebugBuild: false),
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
        .whereBroadwayRoot()
    }
#endif
