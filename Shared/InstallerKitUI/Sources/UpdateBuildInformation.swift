import InstallerKit
import SwiftUI

struct UpdateBuildInformation: View {
    let channel: InstalledBuild.Channel
    let release: UpdateCatalog.Release
    let installed: InstalledBuild
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateCard(title: .installerBuildInformation) {
            UpdatePullRequestLink(channel: channel, installed: installed)
            UpdateWorkflowRunRow(release: release, installed: installed)
            UpdateDetailRow(title: .installerAttempt) {
                Text(verbatim: String(release.id.attempt))
            }
            UpdateCommitRow(revision: release.sha, installed: installed)
            Divider()
            Text(.installerInstallFooter)
                .font(stylesheet.card.bodyFont)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UpdateWorkflowRunRow: View {
    let release: UpdateCatalog.Release
    let installed: InstalledBuild

    var body: some View {
        UpdateDetailRow(title: .installerWorkflowRun) {
            Link(destination: installed.repositoryURL
                .appending(
                    path: "actions/runs/\(release.id.run)/attempts/\(release.id.attempt)",
                )) {
                    Text(verbatim: String(release.id.run))
                }
                .accessibilityHint(String(localized: .installerOpenBuild))
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
