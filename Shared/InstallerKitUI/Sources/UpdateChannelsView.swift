import InstallerKit
import SwiftUI

struct UpdateChannelsView: View {
    let model: UpdateModel
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateBrowserPage(model: model) {
            Text(.installerBrowseMessage)
                .font(stylesheet.card.bodyFont)
                .foregroundStyle(.secondary)
            if let browser = model.state.snapshot?.browser {
                if browser.channels.isEmpty {
                    UpdateCard(title: .installerNoPublishedBuild) {
                        Text(.installerNoActiveBuilds)
                            .font(stylesheet.card.bodyFont)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(browser.channels) { channel in
                    NavigationLink(value: UpdateBrowserView.Route.build(.init(
                        channel: channel.id,
                        build: channel.latest.id,
                    ))) {
                        UpdateCard(title: nil) {
                            UpdateBuildRow(
                                release: channel.latest,
                                kind: .channel(
                                    channel.id,
                                    installed: channel.id == model.installed.publication?.channel,
                                ),
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(String(localized: .installerViewBuild))
                }
            }
            UpdateLocalBuildNotice(isInstalled: model.installed.publication == nil)
        }
        .navigationTitle(String(localized: .installerOtherBuilds))
    }
}

#if DEBUG
    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
