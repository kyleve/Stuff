import SFSafeSymbols
import SwiftUI

/// Gives the privacy settings reference the same inset identity as disclosure rows.
struct PrivacyPassportSettingsReferenceLabel: View {
    let detail: LocalizedStringResource

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        HStack(spacing: style.contentSpacing) {
            Image(systemSymbol: .sliderHorizontal3)
                .font(style.symbolFont)
                .foregroundStyle(.tint)
                .frame(width: style.iconSize, height: style.iconSize)
                .background(.tint.opacity(style.statusFillOpacity), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: style.textSpacing) {
                Text(LocalizedStringResource.settingsDiagnosticsTitle)
                    .font(style.titleFont)
                    .bold()
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(style.detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(.white.opacity(style.fillOpacity), in: RoundedRectangle(
            cornerRadius: style.cornerRadius,
        ))
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .strokeBorder(.tint.opacity(style.strokeOpacity), lineWidth: style.strokeWidth)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        PrivacyPassportCardSurface(tilt: .preview) {
            PrivacyPassportSettingsReferenceLabel(
                detail: .settingsPrivacySettingsAction,
            )
            .padding()
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
