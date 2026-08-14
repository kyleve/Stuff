import SFSafeSymbols
import SwiftUI

/// Presents one active privacy-reporting disclosure as a self-contained status row.
struct PrivacyPassportDisclosureRow: View {
    let disclosure: PrivacyPassportPresentation.Disclosure

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        HStack(alignment: .top, spacing: style.contentSpacing) {
            Image(systemSymbol: disclosure.systemSymbol)
                .font(style.symbolFont)
                .foregroundStyle(.tint)
                .frame(width: style.iconSize, height: style.iconSize)
                .background(.tint.opacity(style.statusFillOpacity), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: style.textSpacing) {
                PrivacyPassportDisclosureHeader(disclosure: disclosure)

                Text(disclosure.detail)
                    .font(style.detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
