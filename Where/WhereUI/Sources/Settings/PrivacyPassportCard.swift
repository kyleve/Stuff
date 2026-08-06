import SwiftUI

/// Reassures the reader that Where's location history stays in their Apple storage.
struct PrivacyPassportCard: View {
    @State private var tilt = TiltProvider()

    var body: some View {
        PassportCard(
            title: .settingsPrivacyTitle,
            detail: .settingsPrivacyDetail,
            sealSystemImage: "lock.shield.fill",
            accessorySystemImage: nil,
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
            PrivacyPassportCard()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
        .whereBroadwayRoot()
    }
#endif
