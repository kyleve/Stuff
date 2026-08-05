import SwiftUI

/// Reassures the reader that Where's location history stays in their Apple storage.
struct PrivacyPassportCard: View {
    var body: some View {
        PassportCard(
            title: .settingsPrivacyTitle,
            detail: .settingsPrivacyDetail,
            sealSystemImage: "lock.shield.fill",
            accessorySystemImage: nil,
            isInteractive: false,
        )
    }
}

#if DEBUG
    #Preview {
        Form {
            PrivacyPassportCard()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .whereBroadwayRoot()
    }
#endif
