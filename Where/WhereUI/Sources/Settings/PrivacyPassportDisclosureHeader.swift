import SFSafeSymbols
import SwiftUI

/// Keeps a disclosure title and status readable as Dynamic Type grows.
struct PrivacyPassportDisclosureHeader: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let showsSettingsIndicator: Bool

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
                if showsSettingsIndicator {
                    Image(systemSymbol: .chevronRight)
                        .font(style.statusFont)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            if showsSettingsIndicator {
                VStack(alignment: .leading, spacing: style.textSpacing) {
                    Text(disclosure.title)
                        .font(style.titleFont)
                        .bold()
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: style.contentSpacing) {
                        Text(disclosure.status)
                            .font(style.statusFont)
                            .bold()
                            .foregroundStyle(.tint)
                            .padding(.horizontal, style.statusHorizontalPadding)
                            .padding(.vertical, style.statusVerticalPadding)
                            .background(.tint.opacity(style.statusFillOpacity), in: Capsule())
                            .fixedSize()
                        Spacer(minLength: 0)
                        Image(systemSymbol: .chevronRight)
                            .font(style.statusFont)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            } else {
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
}

#if DEBUG
    #Preview {
        PrivacyPassportCardSurface(tilt: .preview) {
            PrivacyPassportDisclosureHeader(
                disclosure: .crashReports,
                showsSettingsIndicator: true,
            )
            .padding()
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
