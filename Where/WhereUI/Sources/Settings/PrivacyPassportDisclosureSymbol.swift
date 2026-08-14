import SFSafeSymbols
import SwiftUI

/// Draws the decorative symbol for one privacy disclosure.
struct PrivacyPassportDisclosureSymbol: View {
    let disclosure: PrivacyPassportPresentation.Disclosure

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        Image(systemSymbol: disclosure.systemSymbol)
            .font(style.symbolFont)
            .foregroundStyle(.tint)
            .frame(width: style.iconSize, height: style.iconSize)
            .background(.tint.opacity(style.statusFillOpacity), in: Circle())
            .accessibilityHidden(true)
    }
}
