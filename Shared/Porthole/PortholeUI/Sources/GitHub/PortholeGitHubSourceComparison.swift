import Foundation
import PortholeGitHub

/// Compares installed evidence with the fixed repository base without changing the patch.
struct PortholeGitHubSourceComparison {
    enum State {
        case identical
        case different(String)
        case unavailable(String)
        case failed(String)
    }

    let path: GitHubRepositoryPath
    let state: State

    init(workspace: GitHubSourceWorkspace, path: GitHubRepositoryPath) {
        self.path = path
        guard let installed = workspace.installedSource.files.first(where: { $0.path == path })
        else {
            state = .unavailable("This file was not included in the installed source archive.")
            return
        }
        guard let base = workspace.repositoryBase.files.first(where: { $0.path == path }) else {
            state =
                .unavailable("Load this file from the fixed repository base to compare its source.")
            return
        }
        guard installed != base else { state = .identical; return }
        do {
            let change = try GitHubFileChange(path: path, before: installed, after: base)
            state = try .different(GitHubPatchReview.unifiedDiff(for: [change]))
        } catch { state = .failed(error.localizedDescription) }
    }
}
