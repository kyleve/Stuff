import InstallerKit
import SwiftUI

struct UpdateInstalledBuild: View {
    let model: UpdateModel
    let check: () -> Void

    var body: some View {
        UpdateCard(title: .installerInstalledBuild) {
            UpdateDetailRow(title: .installerChannel) {
                model.installed.source.channelLabel
            }
            switch model.installed.source {
                case let .published(publication):
                    UpdatePublishedBuildRows(publication: publication, installed: model.installed)
                case let .local(.clean(revision)):
                    UpdateWorkingTreeRows(
                        revision: revision,
                        installed: model.installed,
                        status: .installerWorkingTreeClean,
                    )
                case let .local(.dirty(revision)):
                    UpdateWorkingTreeRows(
                        revision: revision,
                        installed: model.installed,
                        status: .installerUncommittedChanges,
                    )
                case .local(.unavailable):
                    UpdateDetailRow(title: .installerCommit) { Text(.installerNotRecorded) }
            }
            Divider()
            if let snapshot = model.state.snapshot {
                UpdateLastCheckedRow(checkedAt: snapshot.checkedAt)
            }
            UpdateCheckButton(isChecking: model.isChecking, check: check)
        }
    }
}

private struct UpdatePublishedBuildRows: View {
    let publication: InstalledBuild.Publication
    let installed: InstalledBuild

    var body: some View {
        UpdatePullRequestLink(channel: publication.channel, installed: installed)
        UpdateDetailRow(title: .installerWorkflowRun) {
            Text(verbatim: String(publication.build.run))
        }
        UpdateDetailRow(title: .installerAttempt) {
            Text(verbatim: String(publication.build.attempt))
        }
        UpdateCommitRow(revision: publication.revision, installed: installed)
    }
}

private struct UpdateWorkingTreeRows: View {
    let revision: InstalledBuild.Revision
    let installed: InstalledBuild
    let status: LocalizedStringResource

    var body: some View {
        UpdateCommitRow(revision: revision, installed: installed)
        UpdateDetailRow(title: .installerWorkingTree) { Text(status) }
    }
}

private struct UpdateLastCheckedRow: View {
    let checkedAt: Date
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateDetailRow(title: .installerLastChecked) {
            Text(
                checkedAt,
                format: .dateTime.month(.abbreviated).day().hour().minute(),
            )
            .font(stylesheet.details.labelFont)
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
