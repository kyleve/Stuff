import InstallerKit
import SwiftUI

struct UpdateCommitRow: View {
    let revision: InstalledBuild.Revision
    let installed: InstalledBuild
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateDetailRow(title: .installerCommit) {
            Link(destination: installed.commitURL(for: revision)) {
                Text(verbatim: String(revision.rawValue.prefix(stylesheet.details.revisionLength)))
            }
            .accessibilityHint(String(localized: .installerOpenCommit))
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
