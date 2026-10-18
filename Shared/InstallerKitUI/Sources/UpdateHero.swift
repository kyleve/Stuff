import InstallerKit
import SwiftUI

struct UpdateHero<Action: View>: View {
    let branding: AppUpdateBranding
    let channelLabel: Text
    @ViewBuilder let action: Action
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.hero
        let layout = style.arrangement == .stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: style.spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: style.spacing))
        layout {
            artwork
            VStack(alignment: .leading, spacing: style.textSpacing) {
                channelLabel
                    .textCase(.uppercase)
                    .font(style.badgeFont)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, style.badgeHorizontalPadding)
                    .padding(.vertical, style.badgeVerticalPadding)
                    .background(style.badgeFill, in: .capsule)
                Text(verbatim: branding.name)
                    .font(style.titleFont)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: branding.subtitle)
                    .font(style.subtitleFont)
                    .foregroundStyle(.secondary)
                action
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var artwork: some View {
        let style = stylesheet.hero
        return ZStack {
            style.iconFill
            if let icon = branding.icon {
                icon.resizable().scaledToFit()
            } else {
                Text(verbatim: String(branding.name.prefix(1)).uppercased())
                    .font(style.monogramFont)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: style.iconSize, height: style.iconSize)
        .clipShape(.rect(cornerRadius: style.iconSize * style.iconCornerRatio))
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
