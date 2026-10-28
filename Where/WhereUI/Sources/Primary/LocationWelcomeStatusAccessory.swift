import SFSafeSymbols
import SwiftUI

/// Compact acquisition or recovery status hosted above the app's tab bar.
struct LocationWelcomeStatusAccessory: View {
    let accessory: LocationWelcomeModel.Accessory

    @Environment(\.openURL) private var openURL
    @Environment(\.stylesheet) private var stylesheet
    @MotionIsStatic private var motionIsStatic

    var body: some View {
        switch accessory {
            case .locating:
                HStack(spacing: style.contentSpacing) {
                    if motionIsStatic {
                        Image(systemSymbol: .locationFill)
                            .font(.system(size: style.symbolSize, weight: .semibold))
                            .accessibilityHidden(true)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(String(localized: .locationWelcomeFinding))
                        .font(style.titleFont)
                }
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, style.verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            case let .actionRequired(action):
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
    }

    private var style: WhereStylesheet.LocationWelcomeStyle.Accessory {
        stylesheet.locationWelcome.accessory
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
    #Preview("Finding") {
        LocationWelcomeStatusAccessory(accessory: .locating)
            .whereBroadwayRoot()
    }

    #Preview("Action required") {
        LocationWelcomeStatusAccessory(accessory: .actionRequired(.preciseLocation))
            .whereBroadwayRoot()
    }
#endif
