import SFSafeSymbols
import SwiftUI

/// Restacks the privacy seal above its title when accessibility text needs the width.
struct PrivacyPassportHeader: View {
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.whereComponentStylesheet) private var components

    var body: some View {
        let style = stylesheet.privacyPassportCard
        if style.headerLayout == .stacked {
            VStack(alignment: .leading, spacing: style.headerSpacing) {
                emblem
                Text(LocalizedStringResource.settingsPrivacyTitle)
                    .font(components[.privacy].heading ?? style.titleFont)
                    .bold()
                    .foregroundStyle(.primary)
            }
        } else {
            HStack(spacing: style.headerSpacing) {
                emblem
                Text(LocalizedStringResource.settingsPrivacyTitle)
                    .font(components[.privacy].heading ?? style.titleFont)
                    .bold()
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder private var emblem: some View {
        if components[.privacy].nativeArtwork.contains(.stamp) {
            PassportSeal(
                systemSymbol: .lockShieldFill,
                tint: stylesheet.privacyPassportCard.reflectiveSurface.accent,
            )
        } else {
            Image(systemSymbol: .lockShieldFill)
                .font(components[.privacy].heading ?? .headline)
                .foregroundStyle(stylesheet.privacyPassportCard.reflectiveSurface.accent)
                .accessibilityHidden(true)
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
