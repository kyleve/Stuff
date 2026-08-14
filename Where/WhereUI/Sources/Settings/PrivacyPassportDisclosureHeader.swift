import SwiftUI

/// Keeps a disclosure title and status readable as Dynamic Type grows.
struct PrivacyPassportDisclosureHeader: View {
    let disclosure: PrivacyPassportPresentation.Disclosure

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: style.contentSpacing) {
                Text(disclosure.title)
                    .font(style.titleFont)
                    .bold()
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(disclosure.status)
                    .font(style.statusFont)
                    .bold()
                    .foregroundStyle(.tint)
                    .padding(.horizontal, style.statusHorizontalPadding)
                    .padding(.vertical, style.statusVerticalPadding)
                    .background(.tint.opacity(style.statusFillOpacity), in: Capsule())
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: style.textSpacing) {
                Text(disclosure.title)
                    .font(style.titleFont)
                    .bold()
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(disclosure.status)
                    .font(style.statusFont)
                    .bold()
                    .foregroundStyle(.tint)
                    .padding(.horizontal, style.statusHorizontalPadding)
                    .padding(.vertical, style.statusVerticalPadding)
                    .background(.tint.opacity(style.statusFillOpacity), in: Capsule())
                    .fixedSize()
            }
        }
    }
}
