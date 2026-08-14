import SwiftUI

/// Keeps one privacy disclosure's status and explanation together.
struct PrivacyPassportDisclosureText: View {
    let disclosure: PrivacyPassportPresentation.Disclosure

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        VStack(alignment: .leading, spacing: style.textSpacing) {
            PrivacyPassportDisclosureHeader(disclosure: disclosure)

            Text(disclosure.detail)
                .font(style.detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
    #Preview {
        PrivacyPassportCardSurface(tilt: .preview) {
            PrivacyPassportDisclosureText(disclosure: .crashReports)
                .padding()
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
