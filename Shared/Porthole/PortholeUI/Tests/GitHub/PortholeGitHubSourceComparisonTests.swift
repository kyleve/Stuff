import Foundation
import PortholeGitHub
@testable import PortholeUI
import Testing

struct PortholeGitHubSourceComparisonTests {
    @Test func comparesInstalledEvidenceWithBaseAndExcludesWorkspaceEdits() throws {
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        var workspace = try GitHubSourceWorkspace(
            installedSource: PortholeGitHubUITestSupport.installed(),
            repositoryBase: PortholeGitHubUITestSupport.base(),
        )
        try workspace.setText("let value = 42\n", at: path, mode: .regular)
        let comparison = PortholeGitHubSourceComparison(workspace: workspace, path: path)
        guard case let .different(diff) = comparison.state else {
            Issue.record("Expected an installed-to-base difference"); return
        }
        #expect(diff.contains("-let value = 99"))
        #expect(diff.contains("+let value = 1"))
        #expect(!diff.contains("42"))
        #expect(workspace.patch.first?.after?.text == "let value = 42\n")
    }

    @Test func identicalAndMissingSourceHaveDistinctHonestStates() throws {
        let base = try PortholeGitHubUITestSupport.base()
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        let same = GitHubSourceWorkspace(
            installedSource: .init(buildIdentity: "same", isDirty: false, files: base.files),
            repositoryBase: base,
        )
        guard case .identical = PortholeGitHubSourceComparison(workspace: same, path: path).state
        else {
            Issue.record("Expected identical source"); return
        }
        let missing = GitHubSourceWorkspace(
            installedSource: .init(buildIdentity: "absent", isDirty: false, files: []),
            repositoryBase: base,
        )
        guard case .unavailable = PortholeGitHubSourceComparison(workspace: missing, path: path)
            .state
        else {
            Issue.record("Missing installed source must not appear identical"); return
        }
    }
}
