import SFSafeSymbols
import SwiftUI

/// Compact acquisition or recovery status hosted above the app's tab bar.
struct LocationWelcomeStatusAccessory: View {
    let accessory: LocationWelcomeModel.Accessory

    @Environment(\.openURL) private var openURL
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @MotionIsStatic private var motionIsStatic

    var body: some View {
        Group {
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(message(for: action))
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        dynamicTypeSize.isAccessibilitySize ? String(localized: .tabSettings) : message(for: action)
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
