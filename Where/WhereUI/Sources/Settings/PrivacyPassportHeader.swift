import SwiftUI

/// Restacks the privacy seal above its title when accessibility text needs the width.
struct PrivacyPassportHeader: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard
        if style.headerLayout == .stacked {
            VStack(alignment: .leading, spacing: style.headerSpacing) {
                PassportSeal(
                    systemSymbol: .lockShieldFill,
                    tint: style.reflectiveSurface.accent,
                )
                Text(LocalizedStringResource.settingsPrivacyTitle)
                    .font(style.titleFont)
                    .bold()
                    .foregroundStyle(.primary)
            }
        } else {
            HStack(spacing: style.headerSpacing) {
                PassportSeal(
                    systemSymbol: .lockShieldFill,
                    tint: style.reflectiveSurface.accent,
                )
                Text(LocalizedStringResource.settingsPrivacyTitle)
                    .font(style.titleFont)
                    .bold()
                    .foregroundStyle(.primary)
            }
        }
    }
}

#if DEBUG
    #Preview {
        PrivacyPassportCardSurface(tilt: .preview) {
            PrivacyPassportHeader()
                .padding()
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
