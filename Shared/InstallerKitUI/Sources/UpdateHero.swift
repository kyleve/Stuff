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
            UpdateHeroArtwork(branding: branding)
            UpdateHeroDetails(branding: branding, channelLabel: channelLabel, action: action)
        }
    }
}

private struct UpdateHeroDetails<Action: View>: View {
    let branding: AppUpdateBranding
    let channelLabel: Text
    let action: Action
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.hero
        VStack(alignment: .leading, spacing: style.textSpacing) {
            UpdateChannelBadge(label: channelLabel)
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

private struct UpdateChannelBadge: View {
    let label: Text
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.hero
        label
            .textCase(.uppercase)
            .font(style.badgeFont)
            .foregroundStyle(.tint)
            .padding(.horizontal, style.badgeHorizontalPadding)
            .padding(.vertical, style.badgeVerticalPadding)
            .background(style.badgeFill, in: .capsule)
    }
}

private struct UpdateHeroArtwork: View {
    let branding: AppUpdateBranding
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.hero
        ZStack {
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
