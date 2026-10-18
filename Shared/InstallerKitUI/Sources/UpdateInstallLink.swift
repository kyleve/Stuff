import InstallerKit
import SwiftUI

struct UpdateInstallLink: View {
    let title: LocalizedStringResource
    let release: UpdateCatalog.Release
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        Link(destination: release.installURL) {
            Text(title)
                .font(stylesheet.hero.actionFont)
                .padding(.horizontal, stylesheet.hero.actionHorizontalPadding)
                .frame(minHeight: stylesheet.hero.actionMinimumHeight)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .accessibilityHint(String(localized: .installerInstallHint))
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
