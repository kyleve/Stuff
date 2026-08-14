import SwiftUI

/// Draws one disclosure row, including its optional in-card settings indicator.
struct PrivacyPassportDisclosureRowLabel: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let showsSettingsIndicator: Bool

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: style.contentSpacing) {
                    PrivacyPassportDisclosureSymbol(disclosure: disclosure)
                    PrivacyPassportDisclosureText(
                        disclosure: disclosure,
                        showsSettingsIndicator: showsSettingsIndicator,
                    )
                }
            } else {
                HStack(alignment: .top, spacing: style.contentSpacing) {
                    PrivacyPassportDisclosureSymbol(disclosure: disclosure)
                    PrivacyPassportDisclosureText(
                        disclosure: disclosure,
                        showsSettingsIndicator: showsSettingsIndicator,
                    )
                }
            }
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            PrivacyPassportDisclosureRowLabel(
                disclosure: .crashReports,
                showsSettingsIndicator: true,
            )
            .padding()
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
