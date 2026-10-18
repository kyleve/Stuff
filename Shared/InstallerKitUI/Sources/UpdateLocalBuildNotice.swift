import SFSafeSymbols
import SwiftUI

/// Explains the locally controlled channel without offering a nonexistent remote download.
struct UpdateLocalBuildNotice: View {
    let isInstalled: Bool
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateCard(title: .installerLocalChannel) {
            if isInstalled {
                Label(String(localized: .installerInstalled), systemSymbol: .checkmarkCircleFill)
                    .font(stylesheet.browser.badgeFont)
                    .foregroundStyle(.tint)
            }
            Text(.installerLocalBuildMessage)
                .font(stylesheet.card.bodyFont)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
