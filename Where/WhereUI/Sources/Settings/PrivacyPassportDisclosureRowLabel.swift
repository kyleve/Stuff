import SFSafeSymbols
import SwiftUI

/// Draws one disclosure row, including its optional in-card settings indicator.
struct PrivacyPassportDisclosureRowLabel: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let showsSettingsIndicator: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        Group {
            if style.layout == .stacked {
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
    #Preview { PrivacyPassportDisclosureRowLabelPreview() }

    private struct PrivacyPassportDisclosureRowLabelPreview: View {
        var body: some View {
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
    }
#endif

/// Draws the decorative symbol for one privacy disclosure.
private struct PrivacyPassportDisclosureSymbol: View {
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

#if DEBUG
    #Preview("Symbol") { PrivacyPassportDisclosureSymbolPreview() }

    private struct PrivacyPassportDisclosureSymbolPreview: View {
        var body: some View {
            PrivacyPassportCardSurface(tilt: .preview) {
                PrivacyPassportDisclosureSymbol(disclosure: .crashReports)
                    .padding()
            }
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif

/// Keeps one privacy disclosure's status and explanation together.
private struct PrivacyPassportDisclosureText: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let showsSettingsIndicator: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        VStack(alignment: .leading, spacing: style.textSpacing) {
            PrivacyPassportDisclosureHeader(
                disclosure: disclosure,
                showsSettingsIndicator: showsSettingsIndicator,
            )

            Text(disclosure.detail)
                .font(style.detailFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
    #Preview("Text") { PrivacyPassportDisclosureTextPreview() }

    private struct PrivacyPassportDisclosureTextPreview: View {
        var body: some View {
            PrivacyPassportCardSurface(tilt: .preview) {
                PrivacyPassportDisclosureText(
                    disclosure: .crashReports,
                    showsSettingsIndicator: true,
                )
                .padding()
            }
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif

/// Keeps a disclosure title and status readable as Dynamic Type grows.
private struct PrivacyPassportDisclosureHeader: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let showsSettingsIndicator: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            PrivacyDisclosureInlineHeader(
                disclosure: disclosure,
                showsSettingsIndicator: showsSettingsIndicator,
            )
            PrivacyDisclosureStackedHeader(
                disclosure: disclosure,
                showsSettingsIndicator: showsSettingsIndicator,
            )
        }
    }
}

private struct PrivacyDisclosureTitle: View {
    let disclosure: PrivacyPassportPresentation.Disclosure

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        Text(disclosure.title)
            .font(style.titleFont)
            .bold()
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PrivacyDisclosureStatus: View {
    let disclosure: PrivacyPassportPresentation.Disclosure

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
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

private struct PrivacyDisclosureIndicator: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        Image(systemSymbol: .chevronRight)
            .font(style.statusFont)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

private struct PrivacyDisclosureInlineHeader: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let showsSettingsIndicator: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        HStack(alignment: .firstTextBaseline, spacing: style.contentSpacing) {
            PrivacyDisclosureTitle(disclosure: disclosure)
            Spacer(minLength: 0)
            PrivacyDisclosureStatus(disclosure: disclosure)
            if showsSettingsIndicator {
                PrivacyDisclosureIndicator()
            }
        }
    }
}

private struct PrivacyDisclosureStackedHeader: View {
    let disclosure: PrivacyPassportPresentation.Disclosure
    let showsSettingsIndicator: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard.disclosure
        VStack(alignment: .leading, spacing: style.textSpacing) {
            PrivacyDisclosureTitle(disclosure: disclosure)
            if showsSettingsIndicator {
                HStack(alignment: .firstTextBaseline, spacing: style.contentSpacing) {
                    PrivacyDisclosureStatus(disclosure: disclosure)
                    Spacer(minLength: 0)
                    PrivacyDisclosureIndicator()
                }
            } else {
                PrivacyDisclosureStatus(disclosure: disclosure)
            }
        }
    }
}

#if DEBUG
    #Preview("Status") { PrivacyPassportDisclosureHeaderPreview() }

    private struct PrivacyPassportDisclosureHeaderPreview: View {
        var body: some View {
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
    }
#endif
