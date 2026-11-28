import SFSafeSymbols
import SwiftUI

struct LocationSettingsButton: View {
    let style: WhereStylesheet.LocationWelcomeStyle.Accessory
    let action: LocationWelcomeModel.ActionRequired
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: openSettings) {
            HStack(spacing: style.contentSpacing) {
                Image(systemSymbol: .locationSlashFill)
                    .font(.system(size: style.symbolSize, weight: .semibold))
                    .accessibilityHidden(true)
                Text(displayedMessage(for: action))
                    .font(style.titleFont)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, style.horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: style.minimumActionHeight,
                alignment: .leading,
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message(for: action))
    }

    private func message(for action: LocationWelcomeModel.ActionRequired) -> String {
        switch action {
            case .locationAccess: String(localized: .locationWelcomeAccessMessage)
            case .preciseLocation: String(localized: .locationWelcomePreciseMessage)
        }
    }

    private func displayedMessage(for action: LocationWelcomeModel.ActionRequired) -> String {
        style.copy == .compact ? compactMessage(for: action) : message(for: action)
    }

    private func compactMessage(for action: LocationWelcomeModel.ActionRequired) -> String {
        switch action {
            case .locationAccess: String(localized: .locationWelcomeAccessCompact)
            case .preciseLocation: String(localized: .locationWelcomePreciseCompact)
        }
    }

    private func openSettings() {
        openSystemSettings(openURL)
    }
}

#if DEBUG
    #Preview("Action required") {
        LocationWelcomeStatusAccessory(accessory: .actionRequired(.preciseLocation))
            .whereBroadwayRoot()
    }
#endif
