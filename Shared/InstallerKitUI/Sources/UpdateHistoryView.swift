import InstallerKit
import SnapshotKit
import SwiftUI

struct UpdateHistoryView: View {
    let model: UpdateModel
    let channel: InstalledBuild.Channel
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateBrowserPage(model: model) {
            if let browser = model.state.snapshot?.browser, let history = browser.channel(channel) {
                Text(verbatim: channel.rawValue.uppercased())
                    .font(stylesheet.card.titleFont)
                    .accessibilityAddTraits(.isHeader)
                Text(.installerHistoryMessage)
                    .font(stylesheet.card.bodyFont)
                    .foregroundStyle(.secondary)
                ForEach(history.releases) { release in
                    let selection = UpdateBuildBrowser.Selection(
                        channel: channel,
                        build: release.id,
                    )
                    NavigationLink(value: UpdateBrowserView.Route.build(selection)) {
                        UpdateCard(title: nil) {
                            UpdateBuildRow(
                                release: release,
                                kind: .release(installed: browser.build(for: selection)?
                                    .isInstalled == true),
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(String(localized: .installerViewBuild))
                }
            } else {
                UpdateCard(title: .installerRetiredTitle) {
                    Text(.installerChannelUnavailableMessage)
                        .font(stylesheet.card.bodyFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: .installerBuildHistory))
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
                InstallerBrowserPreview.navigation(
                    to: .history(InstallerPreview.channel),
                    model: InstallerBrowserPreview.model(.available),
                )
            }
            SnapshotCase(
                name: "Retired",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                InstallerBrowserPreview.navigation(
                    to: .history(InstallerPreview.channel),
                    model: InstallerBrowserPreview.model(.retired),
                )
            }
        }
    }

    #Preview { UpdateHistoryView.snapshotPreviews }
#endif
