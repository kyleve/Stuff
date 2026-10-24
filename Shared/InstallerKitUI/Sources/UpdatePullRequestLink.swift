import InstallerKit
import SwiftUI

/// Shows the PR for the represented build, including when browsing another channel.
struct UpdatePullRequestLink: View {
    let channel: InstalledBuild.Channel
    let installed: InstalledBuild

    var body: some View {
        if let url = installed.pullRequestURL(for: channel) {
            UpdateDetailRow(title: .installerPullRequest) {
                Link(destination: url) {
                    Text(verbatim: "#" + url.lastPathComponent)
                }
                .accessibilityHint(String(localized: .installerOpenPullRequest))
            }
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
