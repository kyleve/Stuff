import InstallerKit
import SwiftUI

struct UpdateChanges: View {
    enum Scope {
        case installedBuild
        case previousBuild
    }

    let changes: UpdateCatalog.Changes
    let installed: InstalledBuild
    var scope = Scope.installedBuild
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateCard(title: scope == .installedBuild ? .installerChanges : .installerBuildChanges) {
            if scope == .previousBuild {
                Text(.installerBuildChangesSubtitle)
                    .font(stylesheet.card.bodyFont)
                    .foregroundStyle(.secondary)
            }
            switch changes {
                case let .commits(commits):
                    UpdateCommitList(commits: commits, installed: installed, scope: scope)
                case .rewritten:
                    Text(scope == .installedBuild ? LocalizedStringResource
                        .installerRewrittenHistory : .installerBuildHistoryRewritten)
                        .font(stylesheet.card.bodyFont)
                case .unavailable:
                    Text(scope == .installedBuild ? LocalizedStringResource
                        .installerHistoryUnavailable : .installerBuildHistoryUnavailable)
                        .font(stylesheet.card.bodyFont)
            }
        }
    }
}

private struct UpdateCommitList: View {
    let commits: [UpdateCatalog.Commit]
    let installed: InstalledBuild
    let scope: UpdateChanges.Scope
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        if scope == .installedBuild {
            Text(.installerChangesSubtitle)
                .font(stylesheet.card.bodyFont)
                .foregroundStyle(.secondary)
        }
        if commits.isEmpty {
            Text(.installerNoCommits)
        } else {
            ForEach(commits) { commit in
                Divider()
                UpdateChangeLink(commit: commit, url: installed.commitURL(for: commit.sha))
            }
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
