import SwiftUI

/// Presents one active privacy-reporting disclosure as a self-contained status row.
struct PrivacyPassportDisclosureRow: View {
    let disclosure: PrivacyPassportPresentation.Disclosure

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: style.contentSpacing) {
                    PrivacyPassportDisclosureSymbol(disclosure: disclosure)
                    PrivacyPassportDisclosureText(disclosure: disclosure)
                }
            } else {
                HStack(alignment: .top, spacing: style.contentSpacing) {
                    PrivacyPassportDisclosureSymbol(disclosure: disclosure)
                    PrivacyPassportDisclosureText(disclosure: disclosure)
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
