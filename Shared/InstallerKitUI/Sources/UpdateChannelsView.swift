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
                UpdateChannelRows(
                    channels: browser.channels,
                    installedChannel: model.installed.publication?.channel,
                )
            }
            UpdateLocalBuildNotice(isInstalled: model.installed.publication == nil)
        }
        .navigationTitle(String(localized: .installerOtherBuilds))
    }
}

private struct UpdateChannelRows: View {
    let channels: [UpdateBuildBrowser.Channel]
    let installedChannel: InstalledBuild.Channel?

    var body: some View {
        if channels.isEmpty {
            UpdateNoticeCard(title: .installerNoPublishedBuild, message: .installerNoActiveBuilds)
        }
        ForEach(channels) { channel in
            UpdateBuildRow(
                selection: .init(channel: channel.id, build: channel.latest.id),
                release: channel.latest,
                kind: .channel(installed: channel.id == installedChannel),
            )
        }
    }
}

#if DEBUG
    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
