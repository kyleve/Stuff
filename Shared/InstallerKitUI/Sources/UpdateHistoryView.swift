import InstallerKit
import SnapshotKit
import SwiftUI

struct UpdateHistoryView: View {
    let model: UpdateModel
    let channel: InstalledBuild.Channel

    var body: some View {
        UpdateBrowserPage(model: model) {
            if let browser = model.state.snapshot?.browser, let history = browser.channel(channel) {
                UpdateHistoryEntries(history: history, browser: browser)
            } else {
                UpdateNoticeCard(
                    title: .installerRetiredTitle,
                    message: .installerChannelUnavailableMessage,
                )
            }
        }
        .navigationTitle(String(localized: .installerBuildHistory))
    }
}

private struct UpdateHistoryEntries: View {
    let history: UpdateBuildBrowser.Channel
    let browser: UpdateBuildBrowser

    var body: some View {
        UpdateHistoryHeader(channel: history.id)
        ForEach(history.releases) { release in
            let selection = UpdateBuildBrowser.Selection(
                channel: history.id,
                build: release.id,
            )
            UpdateBuildRow(
                selection: selection,
                release: release,
                kind: .release(installed: browser.build(for: selection)?
                    .isInstalled == true),
            )
        }
    }
}

private struct UpdateHistoryHeader: View {
    let channel: InstalledBuild.Channel
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        Text(verbatim: channel.rawValue.uppercased())
            .font(stylesheet.card.titleFont)
            .accessibilityAddTraits(.isHeader)
        Text(.installerHistoryMessage)
            .font(stylesheet.card.bodyFont)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    extension UpdateHistoryView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            // Cached fixture history is complete before mounting; automatic refresh
            // stays cache-only. Final settling still covers native navigation chrome.
            SnapshotCase(
                name: "History",
                configurations: .fullContentScreenRepresentative,
                measurementReadiness: .immediate,
            ) {
                InstallerBrowserPreview.Navigation(
                    route: .history(InstallerPreview.channel),
                    model: InstallerBrowserPreview.model(.available),
                )
            }
            SnapshotCase(
                name: "Retired",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                InstallerBrowserPreview.Navigation(
                    route: .history(InstallerPreview.channel),
                    model: InstallerBrowserPreview.model(.retired),
                )
            }
        }
    }

    #Preview { UpdateHistoryView.snapshotPreviews }
#endif
