import InstallerKit
import SwiftUI

struct UpdateBuildInformation: View {
    let release: UpdateCatalog.Release
    let installed: InstalledBuild
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateCard(title: .installerBuildInformation) {
            UpdateDetailRow(title: .installerWorkflowRun) {
                Link(destination: installed.repositoryURL
                    .appending(
                        path: "actions/runs/\(release.id.run)/attempts/\(release.id.attempt)",
                    )) {
                        Text(verbatim: String(release.id.run))
                    }
                    .accessibilityHint(String(localized: .installerOpenBuild))
            }
            UpdateDetailRow(title: .installerAttempt) {
                Text(verbatim: String(release.id.attempt))
            }
            UpdateDetailRow(title: .installerCommit) {
                Link(destination: installed.commitURL(for: release.sha)) {
                    Text(verbatim: String(release.sha.rawValue
                            .prefix(stylesheet.details.revisionLength)))
                }
                .accessibilityHint(String(localized: .installerOpenCommit))
            }
            Divider()
            Text(.installerInstallFooter)
                .font(stylesheet.card.bodyFont)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
